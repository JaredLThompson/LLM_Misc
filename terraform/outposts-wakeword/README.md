# Outposts wake-word training instance

This Terraform root module creates:

- one VPC;
- one subnet on an existing AWS Outpost;
- an internet gateway;
- a public Outpost subnet with automatic public IPv4 assignment;
- a dedicated route table with an internet-gateway default route and optional
  local-gateway route;
- a security group with optional SSH ingress restricted to one administrator
  `/32`;
- a Terraform-generated Ed25519 EC2 key pair whose private key is stored in
  AWS Secrets Manager;
- an EC2 IAM role and instance profile with the AWS-managed
  `AmazonSSMManagedInstanceCore` policy; and
- one EBS-backed GPU EC2 instance on the Outpost.

The stack attaches an internet gateway to the VPC, routes `0.0.0.0/0` to it,
and requests a public IPv4 address for the training instance. It does not
create a NAT gateway, VPC endpoints, or a local gateway.

## Prerequisites

- OpenTofu 1.11.4 (the validated version) or a deliberately tested compatible
  Terraform/OpenTofu release.
- AWS provider credentials with permissions to create the declared resources.
- An existing Outpost and an Outpost subnet-compatible CIDR.
- An AWS GPU Base DLAMI available in the parent Region and launchable on the
  Outpost, or an explicit compatible `ami_id`.
- A launchable G4dn instance size in the Outpost capacity configuration.

The root volume is `gp2`, as required for EBS volumes on Outposts racks. It is
encrypted and deleted with the instance by default. Increase the default
200 GiB size if multiple training datasets or runs will be retained.

Set `ssh_ingress_cidr` to your current trusted public IPv4 address with a
`/32` suffix. Leave it `null` to disable SSH and use Session Manager only.

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

Jupyter runs as `ubuntu`, listens only on the instance loopback interface, and
does not expose an authenticated web service to the subnet or internet. Start
an SSM port-forwarding session from your workstation:

```bash
$(terraform output -raw ssm_jupyter_tunnel_command)
```

Then open `http://127.0.0.1:8889/lab`.

## SSH connectivity

Terraform creates an Ed25519 key pair, registers its public key with EC2, and
stores its private key in Secrets Manager. Retrieve it on your workstation:

```bash
$(terraform output -raw ssh_private_key_download_command)
```

Start an SSH Jupyter tunnel:

```bash
$(terraform output -raw ssh_jupyter_tunnel_command)
```

Then open `http://127.0.0.1:8889/lab`. Direct Jupyter ingress remains closed;
only SSH port 22 is permitted, and only from `ssh_ingress_cidr`.

The private key is marked sensitive by the TLS provider, but because Terraform
generated it, the private key is also present in Terraform state. Use an
encrypted, versioned remote state backend with tightly restricted IAM access;
never commit or share a local state file. Secrets Manager protects retrieval
and provides a controlled operational copy, but it does not remove the key from
state. Rotate the key by replacing the `tls_private_key.ssh` resource.

The bootstrap script creates:

```text
/opt/wakeword/
├── artifacts/
├── cache/
└── runs/
```

Bootstrap refreshes package metadata and installs only the required packages;
it does not run a general OS upgrade. This preserves the known DLAMI
kernel/NVIDIA/CUDA combination and validates `nvidia-smi` before starting
Jupyter. Apply security updates in an explicit maintenance cycle, reboot when
required, revalidate CUDA and model training, then pin or bake the approved AMI.

Use `/opt/wakeword/cache` for the reusable ACAV feature array and AudioSet
background data. Store each parameterized training run under
`/opt/wakeword/runs`, and copy only isolated, validated standalone ONNX models
to `/opt/wakeword/artifacts`.

## SSM connectivity

Attaching `AmazonSSMManagedInstanceCore` provides authorization but not network
reachability. SSM Agent must reach the regional `ssm` and `ssmmessages`
endpoints on TCP 443. Older Regions or older agents may also use
`ec2messages`.

Session Manager connections are initiated outbound by SSM Agent and require no
inbound rule. When `ssh_ingress_cidr` is set, the only inbound rule is TCP/22
from that exact `/32`.

## S3 cache

Set `cache_bucket_name` to create an encrypted, versioned, public-access-blocked
bucket and grant the instance read/write access to it. On boot, objects beneath
`s3://BUCKET/content/` are restored to `/content`. Upload cache contents
explicitly after a successful preparation run:

```bash
aws s3 sync /content/ s3://BUCKET/content/ \
  --exclude 'LLM_Misc/*' \
  --exclude 'my_custom_model/*'
```

The versioned cache bucket is intentionally retained when it contains objects;
empty it deliberately before `terraform destroy` if it should also be removed.

## Destroy

```bash
terraform destroy
```

The root EBS volume has `delete_on_termination = true`. Confirm that no retained
snapshots or separately managed volumes remain if the environment is no longer
needed.
