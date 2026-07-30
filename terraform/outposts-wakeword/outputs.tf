output "vpc_id" {
  description = "ID of the training VPC."
  value       = aws_vpc.this.id
}

output "outpost_subnet_id" {
  description = "ID of the Outpost subnet."
  value       = aws_subnet.outpost.id
}

output "instance_id" {
  description = "ID of the GPU training instance."
  value       = aws_instance.training.id
}

output "resolved_ami_id" {
  description = "Explicit or automatically selected GPU AMI ID."
  value       = local.resolved_ami_id
}

output "resolved_ami_name" {
  description = "Name of the automatically selected AMI, or null when ami_id was supplied explicitly."
  value       = try(data.aws_ami.gpu[0].name, null)
}

output "instance_private_ip" {
  description = "Private IPv4 address of the GPU training instance."
  value       = aws_instance.training.private_ip
}

output "instance_public_ip" {
  description = "Public IPv4 address of the GPU training instance."
  value       = aws_instance.training.public_ip
}

output "instance_role_name" {
  description = "IAM role attached to the GPU training instance."
  value       = aws_iam_role.training.name
}

output "ssm_start_session_command" {
  description = "AWS CLI command used to start a Session Manager shell."
  value       = "aws ssm start-session --region ${var.aws_region} --target ${aws_instance.training.id}"
}
