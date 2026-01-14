
# IAM role for the eks master nodes
resource "aws_iam_role" "eks_cluster" {
  name = "nca-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
      Action   = "sts:AssumeRole"
      Effect = "Allow",
      Principal = { Service = "eks.amazonaws.com" },
    }
    ]
  })

  tags = var.tags
}
# this policy allows EKS control plane to have necessary permissions for managing the cluster
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

#IAM role for EKS worker nodes 
resource "aws_iam_role" "eks_node" {
  name = "nca-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action   = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}
# this policy allows EKS worker nodes to join the cluster
resource "aws_iam_role_policy_attachment" "eks_worker" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}
# this cni (container networking interface) policy allow the pods running on the worker nodes to get ip addresses and communicate over the VPC network
resource "aws_iam_role_policy_attachment" "eks_cni" {
  role       = aws_iam_role.eks_node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# eks sercurity groups  
resource "aws_security_group" "eks_cluster" {
  name        = "nca-eks-cluster-sg"
  description = "EKS control plane"
  vpc_id      = aws_vpc.this.id

  # allow inbound traffic only from within the VPC CIDR block on port 443 (EKS API server)
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
# allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

}

# EKS cluster (control plane/master node)
resource "aws_eks_cluster" "this" {
  name     = "nca-eks"
  role_arn = aws_iam_role.eks_cluster.arn
  version  = "1.33"  
# specify the subnets and security groups for the EKS cluster
  vpc_config { 
    subnet_ids = [
      aws_subnet.app_a.id,
      aws_subnet.app_b.id,
    ]
    security_group_ids      = [aws_security_group.eks_cluster.id]
    endpoint_public_access  = true # this allows kubectl access from the Internet
    endpoint_private_access = true # this allows access from within the VPC
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
}

# EKS Managed Node Group (worker nodes)
resource "aws_eks_node_group" "this" {
  cluster_name    = aws_eks_cluster.this.name # attach the node group to the EKS cluster created earlier
  node_group_name = "nca-eks-ng"
  node_role_arn   = aws_iam_role.eks_node.arn # attach the iam role created earlier to the worker nodes
  subnet_ids = [
    aws_subnet.app_a.id,
    aws_subnet.app_b.id,
  ]

  scaling_config {
    desired_size = 2
    max_size     = 3
    min_size     = 1
  }
  # make sure only one node is updated at a time during updates
  update_config {
    max_unavailable = 1
  }

  instance_types = ["t2.medium"] 

  ami_type  = "AL2_x86_64" # this ami auotmacally includes the kubelet, kube-proxy, CNI plugins needed for EKS worker nodes
  disk_size = 20

  depends_on = [
    aws_iam_role_policy_attachment.eks_worker,
    aws_iam_role_policy_attachment.eks_cni,
    aws_iam_role_policy_attachment.eks_ecr_readonly
  ]
}

# Retrieve the API endpoint and certificate for the EKS cluster to configure the Kubernetes provider
data "aws_eks_cluster" "this" {
  name = aws_eks_cluster.this.name
}
# Retrieve authentication token for the EKS cluster
data "aws_eks_cluster_auth" "this" {
  name = aws_eks_cluster.this.name
}
# Configure the Kubernetes provider so Terraform can create resources inside the EKS cluster
provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.this.token
}
