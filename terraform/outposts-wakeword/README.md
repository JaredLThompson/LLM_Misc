# Outposts wake-word training instance

This Terraform root module creates:

- one VPC;
- one subnet on an existing AWS Outpost;
- an internet gateway;
- a public Outpost subnet with automatic public IPv4 assignment;
- a dedicated route table with an internet-gateway default route and optional
  local-gateway route;
- a no-ingress security group;
- an EC2 IAM role and instance profile with the AWS-managed
  `AmazonSSMManagedInstanceCore` policy; and
- one EBS-backed GPU EC2 instance on the Outpost.

The stack attaches an internet gateway to the VPC, routes `0.0.0.0/0` to it,
and requests a public IPv4 address for the training instance. It does not
create a NAT gateway, VPC endpoints, or a local gateway.

## Prerequisites

- Terraform 1.6 or newer.
- AWS provider credentials with permissions to create the declared resources.
- An existing Outpost and an Outpost subnet-compatible CIDR.
- An AWS GPU Base DLAMI available in the parent Region and launchable on the
  Outpost, or an explicit compatible `ami_id`.
- A launchable G4dn instance size in the Outpost capacity configuration.

The root volume is `gp2`, as required for EBS volumes on Outposts racks. It is
encrypted and deleted with the instance by default. Increase the default
200 GiB size if multiple training datasets or runs will be retained.

## Deploy

```bash
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars

terraform init
terraform fmt -check
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

By default, Terraform selects the newest AWS-owned x86-64 image matching:

```text
Deep Learning Base AMI with Single CUDA (Ubuntu 24.04)*
```

This DLAMI family includes NVIDIA drivers and SSM Agent and supports G4dn.
Set `ami_id` explicitly to pin a tested image and prevent a newer published
DLAMI from causing instance replacement in a future plan.

Start a Session Manager shell with the rendered output:

```bash
terraform output -raw ssm_start_session_command
```

Or run it directly:

```bash
aws ssm start-session \
  --region REGION \
  --target "$(terraform output -raw instance_id)"
```

The bootstrap script creates:

```text
/opt/wakeword/
├── artifacts/
├── cache/
└── runs/
```

Use `/opt/wakeword/cache` for the reusable ACAV feature array and AudioSet
background data. Store each parameterized training run under
`/opt/wakeword/runs`, and copy only isolated, validated standalone ONNX models
to `/opt/wakeword/artifacts`.

## SSM connectivity

Attaching `AmazonSSMManagedInstanceCore` provides authorization but not network
reachability. SSM Agent must reach the regional `ssm` and `ssmmessages`
endpoints on TCP 443. Older Regions or older agents may also use
`ec2messages`.

There are intentionally no inbound security-group rules. Session Manager
connections are initiated outbound by SSM Agent.

## Destroy

```bash
terraform destroy
```

The root EBS volume has `delete_on_termination = true`. Confirm that no retained
snapshots or separately managed volumes remain if the environment is no longer
needed.
