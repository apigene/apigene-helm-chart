variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane."
  type        = string
  default     = "1.37"
}

variable "vpc_id" {
  description = "VPC ID for the EKS cluster."
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the EKS control plane."
  type        = list(string)
}

variable "node_subnet_ids" {
  description = "Subnet IDs for EKS worker nodes (typically private subnets)."
  type        = list(string)
  default     = []
}

variable "node_instance_types" {
  description = "EC2 instance types for the managed node group."
  type        = list(string)
  default     = ["t3.large"]
}

variable "node_desired_size" {
  description = "Desired number of worker nodes."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
  default     = 4
}

variable "tags" {
  description = "Tags applied to EKS resources."
  type        = map(string)
  default     = {}
}

variable "enable_ebs_csi_driver" {
  description = "Install the AWS EBS CSI driver addon for gp3 StorageClass support."
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Expose the Kubernetes API endpoint publicly (restricted by public_access_cidrs)."
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public Kubernetes API endpoint. Narrow this to your admin networks."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "cluster_log_types" {
  description = "EKS control plane log types sent to CloudWatch Logs."
  type        = list(string)
  default     = ["api", "audit", "authenticator"]
}

variable "enable_network_policy" {
  description = "Enable NetworkPolicy enforcement in the VPC CNI add-on."
  type        = bool
  default     = true
}
