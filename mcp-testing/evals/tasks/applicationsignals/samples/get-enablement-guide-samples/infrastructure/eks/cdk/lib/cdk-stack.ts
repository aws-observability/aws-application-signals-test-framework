import * as cdk from 'aws-cdk-lib';
import * as eks from 'aws-cdk-lib/aws-eks';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import { KubectlV30Layer } from '@aws-cdk/lambda-layer-kubectl-v30';
import { Construct } from 'constructs';

export interface AppConfig {
  appName: string;
  imageName: string;
  language: string;
  port: number;
  healthCheckPath: string;
}

export class EKSAppStack extends cdk.Stack {
  constructor(scope: Construct, id: string, config: AppConfig, props?: cdk.StackProps) {
    super(scope, id, props);

    const ecrImageUri = `${this.account}.dkr.ecr.${this.region}.amazonaws.com/${config.imageName}:latest`;

    const vpc = ec2.Vpc.fromLookup(this, 'DefaultVPC', {
      isDefault: true,
    });

    // IAM role for EKS nodes with same permissions as EC2
    const nodeRole = new iam.Role(this, 'NodeRole', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKSWorkerNodePolicy'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKS_CNI_Policy'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEC2ContainerRegistryReadOnly'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonS3ReadOnlyAccess'),
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
    });

    const cluster = new eks.Cluster(this, 'AppCluster', {
      vpc,
      version: eks.KubernetesVersion.V1_30,
      defaultCapacity: 0,
      kubectlLayer: new KubectlV30Layer(this, 'KubectlLayer'),
      vpcSubnets: [{
        subnetType: ec2.SubnetType.PUBLIC,
        onePerAz: true,
      }],
    });

    // Add access for Admin and ReadOnly roles
    cluster.awsAuth.addRoleMapping(iam.Role.fromRoleArn(this, 'AdminRole', `arn:aws:iam::${this.account}:role/Admin`), {
      groups: ['system:masters'],
    });

    cluster.awsAuth.addRoleMapping(iam.Role.fromRoleArn(this, 'ReadOnlyRole', `arn:aws:iam::${this.account}:role/ReadOnly`), {
      groups: ['system:authenticated'],
    });

    // Create launch template with IMDSv2 hop limit configuration
    const launchTemplate = new ec2.CfnLaunchTemplate(this, 'NodeGroupLaunchTemplate', {
      launchTemplateData: {
        metadataOptions: {
          httpPutResponseHopLimit: 2,
          httpTokens: 'required',
        },
      },
    });

    // Create node group using CfnNodegroup to support launch template
    const nodeGroup = new eks.CfnNodegroup(this, 'DefaultNodeGroup', {
      clusterName: cluster.clusterName,
      nodeRole: nodeRole.roleArn,
      subnets: vpc.publicSubnets.map(subnet => subnet.subnetId),
      instanceTypes: ['t3.medium'],
      scalingConfig: {
        minSize: 1,
        maxSize: 1,
        desiredSize: 1,
      },
      launchTemplate: {
        id: launchTemplate.ref,
        version: launchTemplate.attrLatestVersionNumber,
      },
    });

    nodeGroup.addDependency(cluster.node.defaultChild as cdk.CfnResource);

    const deployment = {
      apiVersion: 'apps/v1',
      kind: 'Deployment',
      metadata: { 
        name: config.appName
      },
      spec: {
        replicas: 1,
        selector: { matchLabels: { app: config.appName } },
        template: {
          metadata: { labels: { app: config.appName } },
          spec: {
            containers: [{
              name: config.appName,
              image: ecrImageUri,
              ports: [{ containerPort: config.port }],
              env: [
                { name: 'PORT', value: config.port.toString() },
                { name: 'AWS_REGION', value: this.region }
              ],
              lifecycle: {
                postStart: {
                  exec: {
                    command: ['sh', '-c', 'nohup bash /app/generate-traffic.sh > /dev/null 2>&1 &']
                  }
                }
              }
            }]
          }
        }
      }
    };

    const service = {
      apiVersion: 'v1',
      kind: 'Service',
      metadata: { 
        name: `${config.appName}-service`
      },
      spec: {
        type: 'LoadBalancer',
        ports: [{ port: config.port, targetPort: config.port }],
        selector: { app: config.appName }
      }
    };

    const appDeployment = cluster.addManifest('AppDeployment', deployment);
    const appService = cluster.addManifest('AppService', service);

    // Ensure manifests are deployed after node group is ready
    appDeployment.node.addDependency(nodeGroup);
    appService.node.addDependency(nodeGroup);

    new cdk.CfnOutput(this, 'ClusterName', {
      value: cluster.clusterName,
      description: 'EKS Cluster Name',
    });

    new cdk.CfnOutput(this, 'ECRImageURI', {
      value: ecrImageUri,
      description: 'ECR image URI used',
    });

    new cdk.CfnOutput(this, 'Language', {
      value: config.language,
      description: 'Application language',
    });
  }
}