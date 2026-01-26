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
  platform?: 'linux' | 'windows';
}

export class EKSAppStack extends cdk.Stack {
  constructor(scope: Construct, id: string, config: AppConfig, props?: cdk.StackProps) {
    super(scope, id, props);

    // Default to linux if platform not specified
    const platform = config.platform || 'linux';
    const isWindows = platform === 'windows';

    const ecrImageUri = `${this.account}.dkr.ecr.${this.region}.amazonaws.com/${config.imageName}:latest`;

    const vpc = ec2.Vpc.fromLookup(this, 'DefaultVPC', {
      isDefault: true,
    });

    // Filter out problematic AZs that don't support EKS
    const eksUnsupportedAzs = ['us-east-1e'];
    const availableSubnets = vpc.publicSubnets.filter(subnet =>
      !eksUnsupportedAzs.includes(subnet.availabilityZone)
    );

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
      defaultCapacity: isWindows ? 1 : 0, // Windows requires Linux nodes for system pods
      kubectlLayer: new KubectlV30Layer(this, 'KubectlLayer'),
      vpcSubnets: [{
        subnets: availableSubnets,
      }],
    });

    // Add access for Admin and ReadOnly roles
    cluster.awsAuth.addRoleMapping(iam.Role.fromRoleArn(this, 'AdminRole', `arn:aws:iam::${this.account}:role/Admin`), {
      groups: ['system:masters'],
    });

    cluster.awsAuth.addRoleMapping(iam.Role.fromRoleArn(this, 'ReadOnlyRole', `arn:aws:iam::${this.account}:role/ReadOnly`), {
      groups: ['system:authenticated'],
    });

    if (isWindows) {
      cluster.awsAuth.addRoleMapping(nodeRole, {
        groups: ['system:bootstrappers', 'system:nodes', 'eks:kube-proxy-windows'],
        username: 'system:node:{{EC2PrivateDNSName}}'
      });

      // Configure the VPC CNI Add-on using the native CfnAddon
      new eks.CfnAddon(this, 'VpcCniAddonWindowsConfig', {
        addonName: 'vpc-cni',
        clusterName: cluster.clusterName,
        // The configurationValues must be a JSON string of the configuration schema
        configurationValues: JSON.stringify({
          "enableWindowsIpam": "true"
        }),
        // Overwrite any default settings if necessary
        resolveConflicts: "OVERWRITE",
      });

      cluster.role.addManagedPolicy(
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonEKSVPCResourceController')
      );
    }


    // Create launch template with IMDSv2 hop limit configuration
    const launchTemplate = new ec2.CfnLaunchTemplate(this, 'NodeGroupLaunchTemplate', {
      launchTemplateData: {
        metadataOptions: {
          httpPutResponseHopLimit: 3,
          httpTokens: 'required',
        },
      },
    });

    // Create node group using CfnNodegroup to support launch template
    const nodeGroup = new eks.CfnNodegroup(this, 'DefaultNodeGroup', {
      clusterName: cluster.clusterName,
      nodeRole: nodeRole.roleArn,
      subnets: availableSubnets.map(subnet => subnet.subnetId),
      instanceTypes: isWindows ? ['t3.large'] : ['t3.medium'], // Windows needs larger instances
      scalingConfig: {
        minSize: 1,
        maxSize: 1,
        desiredSize: 1,
      },
      launchTemplate: {
        id: launchTemplate.ref,
        version: launchTemplate.attrLatestVersionNumber,
      },
      // Set AMI type based on platform
      amiType: isWindows ? 'WINDOWS_CORE_2022_x86_64' : 'AL2_x86_64',
      ...(isWindows && {
        taints: [{
          key: 'os',
          value: 'windows',
          effect: 'NO_SCHEDULE',
        }],
      }),
    });

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
            // Add node selector for platform
            nodeSelector: {
              'kubernetes.io/os': platform
            },
            ...(isWindows && {
              tolerations: [{
                key: 'os',
                value: 'windows',
                effect: 'NoSchedule',
              }],
            }),
            containers: [{
              name: config.appName,
              image: ecrImageUri,
              ports: [{ containerPort: config.port }],
              env: [
                { name: 'PORT', value: config.port.toString() },
                { name: 'AWS_REGION', value: this.region }
              ],
              lifecycle: isWindows ? {
                postStart: {
                  exec: {
                    command: ['powershell', '-Command', 'Start-Process powershell -ArgumentList "-File C:\\app\\generate-traffic.ps1" -WindowStyle Hidden']
                  }
                }
              } : {
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

    new cdk.CfnOutput(this, 'Platform', {
      value: platform,
      description: 'Application platform (linux/windows)',
    });
  }
}