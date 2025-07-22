#!/bin/bash
set -ex 

TESTING_ID=$1
EC2_NAME=$2
REGION=$3

INSTANCE_PROFILE="APP_SIGNALS_EC2_TEST_ROLE"
MASTER_INSTANCE_NAME="k8s-on-ec2-${EC2_NAME}-master-${TESTING_ID}"
WORKER_INSTANCE_NAME="k8s-on-ec2-${EC2_NAME}-worker-${TESTING_ID}"
KEY_NAME="k8s-on-ec2-${EC2_NAME}-key-pair-${TESTING_ID}"

function create_resources() {
    echo "Creating Key Pair"
    aws ec2 create-key-pair --key-name "${KEY_NAME}" --query 'KeyMaterial' --output text > "${KEY_NAME}.pem"
    chmod 400  "${KEY_NAME}.pem"

    # Fetch the latest Amazon Linux 2 AMI ID
    echo "Fetching Latest Image Id"
    image_id=$(aws ec2 describe-images \
      --region $REGION \
      --owners amazon \
      --filters "Name=name,Values=al2023-ami-minimal-*-x86_64" "Name=state,Values=available" \
      --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
      --output text)

    default_vpc_id=$(aws ec2 describe-vpcs --filters Name=isDefault,Values=true --query 'Vpcs[0].VpcId' --output text)
    security_group_id=$(aws ec2 describe-security-groups --filters "Name=vpc-id,Values=$default_vpc_id" "Name=group-name,Values=default" --query "SecurityGroups[0].GroupId" --output text)

    # Create Master EC2 Instance
    echo "Creating Master Instance"
    master_instance_id=$(aws ec2 run-instances \
      --image-id $image_id \
      --count 1 \
      --instance-type m5.xlarge \
      --key-name $KEY_NAME \
      --security-group-ids $security_group_id \
      --iam-instance-profile Name=$INSTANCE_PROFILE \
      --associate-public-ip-address \
      --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=80,VolumeType=gp3}' \
      --metadata-options 'HttpPutResponseHopLimit=3,HttpEndpoint=enabled' \
      --query 'Instances[0].InstanceId' \
      --output text)

    aws ec2 create-tags --resources $master_instance_id --tags Key=Name,Value=$MASTER_INSTANCE_NAME Key=k8s-on-ec2-node,Value=true

    echo "Creating Worker Instance"
    worker_instance_id=$(aws ec2 run-instances \
      --image-id $image_id \
      --count 1 \
      --instance-type m5.xlarge \
      --key-name $KEY_NAME \
      --security-group-ids $security_group_id \
      --iam-instance-profile Name=$INSTANCE_PROFILE \
      --associate-public-ip-address \
      --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=80,VolumeType=gp3}' \
      --metadata-options 'HttpPutResponseHopLimit=3,HttpEndpoint=enabled' \
      --query 'Instances[0].InstanceId' \
      --output text)

    aws ec2 create-tags --resources $worker_instance_id --tags Key=Name,Value=$WORKER_INSTANCE_NAME Key=k8s-on-ec2-node,Value=true

    echo "Wait for Master Instance $master_instance_id and Worker Instance $worker_instance_id to be ready"
    aws ec2 wait instance-status-ok --instance-ids $master_instance_id
    aws ec2 wait instance-status-ok --instance-ids $worker_instance_id
    echo "All instances are up and running."
}


function run_k8s_master() {
  # Retrieve public IP of k8s master node
  master_ip=$(aws ec2 describe-instances \
      --filters "Name=tag:Name,Values=$MASTER_INSTANCE_NAME" "Name=instance-state-name,Values=running" \
      --query "Reservations[*].Instances[*].PublicIpAddress" \
      --output text)

  # SSH and run commands on the master node
  master_private_ip=$(aws ec2 describe-instances \
      --filters "Name=tag:Name,Values=$MASTER_INSTANCE_NAME" "Name=instance-state-name,Values=running" \
      --query "Reservations[*].Instances[*].PrivateIpAddress" \
      --output text)

  worker_private_ip=$(aws ec2 describe-instances \
      --filters "Name=tag:Name,Values=$WORKER_INSTANCE_NAME" "Name=instance-state-name,Values=running" \
      --query "Reservations[*].Instances[*].PrivateIpAddress" \
      --output text)

  # set up kubeadmin
  ssh -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" ec2-user@$master_ip << EOF
    sudo yum update -y && sudo yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
    sudo yum install docker tmux git vim -y && sudo usermod -aG docker ec2-user
    sudo systemctl enable docker && sudo systemctl start docker
    sudo containerd config default > config.toml
    sudo cp config.toml /etc/containerd/config.toml
    sudo sed -i "/^[[:space:]]*\\[plugins\\.'io\\.containerd\\.cri\\.v1\\.runtime'\\.containerd\\.runtimes\\.runc\\.options\\]/a\            SystemdCgroup = true" /etc/containerd/config.toml
    sudo systemctl restart containerd && sleep 20
    sudo setenforce 0 && sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
    echo -e "[kubernetes]\nname=Kubernetes\nbaseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/\nenabled=1\ngpgcheck=1\ngpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key\nexclude=kubelet kubeadm kubectl cri-tools kubernetes-cni" | sudo tee /etc/yum.repos.d/kubernetes.repo
    sudo yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
    sudo systemctl enable --now kubelet && sudo systemctl restart kubelet && sleep 30
    sudo kubeadm init --pod-network-cidr=192.168.0.0/16 --apiserver-advertise-address=$master_private_ip --apiserver-cert-extra-sans=$worker_private_ip
    mkdir -p \$HOME/.kube
    sudo cp -i /etc/kubernetes/admin.conf \$HOME/.kube/config
    sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config
    sleep 120
    curl https://raw.githubusercontent.com/projectcalico/calico/v3.27.2/manifests/calico.yaml -O
    kubectl apply -f calico.yaml && sleep 60
    sudo cd \$HOME
    sudo cp /etc/kubernetes/pki/apiserver.crt apiserver.crt
    sudo cp /etc/kubernetes/pki/apiserver.key apiserver.key
    sudo chmod +r apiserver.key
    sudo kubeadm token create --print-join-command > join-cluster.sh
    sudo chmod +x join-cluster.sh
    echo "tlsCertFile: /etc/kubernetes/pki/apiserver.crt" | sudo tee -a /var/lib/kubelet/config.yaml
    echo "tlsPrivateKeyFile: /etc/kubernetes/pki/apiserver.key" | sudo tee -a /var/lib/kubelet/config.yaml
    sudo systemctl restart kubelet
EOF

  scp -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" ec2-user@$master_ip:~/apiserver.crt . 
  scp -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" ec2-user@$master_ip:~/apiserver.key . 
  scp -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" ec2-user@$master_ip:~/join-cluster.sh . 

}

function run_k8s_worker() {
  # Retrieve public IP of worker node
  worker_ip=$(aws ec2 describe-instances \
      --filters "Name=tag:Name,Values=$WORKER_INSTANCE_NAME" "Name=instance-state-name,Values=running" \
      --query "Reservations[*].Instances[*].PublicIpAddress" \
      --output text)

  scp -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" apiserver.crt ec2-user@$worker_ip:~
  scp -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" apiserver.key ec2-user@$worker_ip:~
  scp -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" join-cluster.sh ec2-user@$worker_ip:~

  # set up kubeadmin
  ssh -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" ec2-user@$worker_ip << EOF
    sudo yum update -y && sudo yum install -y https://s3.amazonaws.com/ec2-downloads-windows/SSMAgent/latest/linux_amd64/amazon-ssm-agent.rpm
    sudo yum install docker tmux git vim -y && sudo usermod -aG docker ec2-user
    sudo systemctl enable docker && sudo systemctl start docker &&  \
    sudo containerd config default > config.toml
    sudo cp config.toml /etc/containerd/config.toml
    sudo sed -i "/^[[:space:]]*\\[plugins\\.'io\\.containerd\\.cri\\.v1\\.runtime'\\.containerd\\.runtimes\\.runc\\.options\\]/a\            SystemdCgroup = true" /etc/containerd/config.toml
    sudo systemctl restart containerd
    sudo setenforce 0 && sudo sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
    echo -e "[kubernetes]\nname=Kubernetes\nbaseurl=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/\nenabled=1\ngpgcheck=1\ngpgkey=https://pkgs.k8s.io/core:/stable:/v1.29/rpm/repodata/repomd.xml.key\nexclude=kubelet kubeadm kubectl cri-tools kubernetes-cni" | sudo tee /etc/yum.repos.d/kubernetes.repo
    sleep 60
    sudo yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
    sudo mkdir -p /etc/kubernetes/pki/
    sudo cp apiserver.crt /etc/kubernetes/pki/apiserver.crt
    sudo cp apiserver.key /etc/kubernetes/pki/apiserver.key
    sudo bash join-cluster.sh && sleep 30
    echo "tlsCertFile: /etc/kubernetes/pki/apiserver.crt" | sudo tee -a /var/lib/kubelet/config.yaml
    echo "tlsPrivateKeyFile: /etc/kubernetes/pki/apiserver.key" | sudo tee -a /var/lib/kubelet/config.yaml
    sudo systemctl restart kubelet
EOF

sleep 300
}

function install_helm() {
  # Retrieve public IP of master node
  master_ip=$(aws ec2 describe-instances \
      --filters "Name=tag:Name,Values=$MASTER_INSTANCE_NAME" "Name=instance-state-name,Values=running" \
      --query "Reservations[*].Instances[*].PublicIpAddress" \
      --output text)

  ssh -o StrictHostKeyChecking=no -i "${KEY_NAME}.pem" ec2-user@$master_ip << EOF
    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.12.0/cert-manager.yaml
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh && sleep 30
    sudo yum install wget -y && \
    sudo wget https://github.com/mikefarah/yq/releases/download/v4.31.2/yq_linux_amd64 -O /usr/bin/yq && \
    sudo chmod +x /usr/bin/yq
EOF

}

create_resources
run_k8s_master
run_k8s_worker
install_helm
