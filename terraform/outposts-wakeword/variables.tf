variable "aws_region" {
  description = "Parent AWS Region for the Outpost."
  type        = string
}

variable "name" {
  description = "Name prefix for resources."
  type        = string
  default     = "wakeword-training"
}

variable "vpc_cidr" {
  description = "CIDR block for the training VPC."
  type        = string
  default     = "10.80.0.0/16"
}

variable "outpost_subnet_cidr" {
  description = "CIDR block for the Outpost subnet."
  type        = string
  default     = "10.80.1.0/24"
}

variable "availability_zone" {
  description = "Availability Zone associated with the Outpost."
  type        = string
}

variable "outpost_arn" {
  description = "ARN of the target Outpost."
  type        = string

  validation {
    condition     = can(regex("^arn:[^:]+:outposts:", var.outpost_arn))
    error_message = "outpost_arn must be an AWS Outposts ARN."
  }
}

variable "ami_id" {
  description = "Optional explicit GPU AMI ID. Null selects the newest AWS-owned AMI matching ami_name_pattern."
  type        = string
  default     = null

  validation {
    condition     = var.ami_id == null || can(regex("^ami-[0-9a-fA-F]+$", var.ami_id))
    error_message = "ami_id must be null or look like an EC2 AMI ID."
  }
}

variable "ami_name_pattern" {
  description = "AMI name glob used when ami_id is null."
  type        = string
  default     = "Deep Learning Base AMI with Single CUDA (Ubuntu 24.04)*"
}

variable "instance_type" {
  description = "Exact G4dn instance type configured and available on the Outpost."
  type        = string
}

variable "root_volume_size_gib" {
  description = "Persistent gp2 root volume size. Holds cached training datasets and artifacts."
  type        = number
  default     = 200

  validation {
    condition     = var.root_volume_size_gib >= 50
    error_message = "root_volume_size_gib must be at least 50 GiB."
  }
}

variable "root_volume_kms_key_id" {
  description = "Optional KMS key ARN or ID for root-volume encryption. Null uses the account default EBS key."
  type        = string
  default     = null
}

variable "local_gateway_id" {
  description = "Optional Outpost local gateway ID for the on-premises route."
  type        = string
  default     = null
}

variable "on_premises_cidr" {
  description = "Optional on-premises destination CIDR routed through local_gateway_id."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags applied to all supported resources."
  type        = map(string)
  default = {
    Application = "wakeword-training"
    ManagedBy   = "terraform"
  }
}
