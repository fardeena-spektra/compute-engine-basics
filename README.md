# Compute Engine Basics

## Summary

Compute Engine Basics is a 90-minute intermediate GCP assessment. Learners enter the provided Google Cloud project through the Windows `labvm`, use the Google Cloud console to create and verify a Linux Compute Engine instance, then connect from PowerShell with `gcloud compute ssh` and create the required completion artifact.

The learner-created target is fixed as follows:

• Instance name: `ubuntu-vm`
• Zone: `us-central1-a`
• Machine type: `e2-micro`
• Boot image: latest available Ubuntu LTS image in the console
• Network: deployment-specific custom-mode VPC provisioned for the lab
• Subnet: `us-central1`, IPv4 range `10.10.0.0/24`
• External address: ephemeral external IPv4
• SSH exposure: TCP/22 from `0.0.0.0/0`, scoped to the learner VM by the expected network tag
• Completion file: `scenario2.txt` in the default GCP user’s home directory
• Exact completion content: `scenario 2 is completed` followed by a normal line ending

The SSH rule and internet exposure are intentionally simple and are for this disposable lab only.

## What the Package Contains

### Deployment and environment

One GCP Deployment Manager YAML stage provisions the learner prerequisites:

1. A dedicated custom VPC whose resource names include the literal `@deploymentId` token.
2. A `us-central1` subnet with CIDR `10.10.0.0/24`.
3. A firewall rule allowing TCP/22 from `0.0.0.0/0` for the learner VM network tag.
4. The Windows `labvm` in `us-central1-a`, using the lab-standard image and `e2-medium` sizing.
5. A Windows startup/bootstrap script that creates a Microsoft Edge desktop shortcut to `https://console.cloud.google.com`.
6. Outputs for the project, lab VM public/private IPs, network, and subnet identifiers.

The sibling `DeploymentPackage/gcp.parameters.yaml` uses `GET-DEPLOYMENT-ID` and `GET-PROJECT-ID`. The learner-created `ubuntu-vm` is not deployed by infrastructure.

### Exercises

1. **Create the Linux Compute Engine VM** — Create and verify `ubuntu-vm` in `us-central1-a` with the required machine type, Ubuntu LTS image, deployment-specific network/subnet, ephemeral external IPv4, SSH network tag, and running state.
2. **Connect with gcloud SSH and create the completion file** — From PowerShell on `labvm`, confirm the project, run `gcloud compute ssh ubuntu-vm --zone us-central1-a`, resolve the default Linux user home directory without hard-coding a username, and create and verify `scenario2.txt`.

### Assessment content

The package includes three PowerShell validators and three intermediate single-choice questions.

The validators check:

• VM identity, zone, and `RUNNING` lifecycle state.
• `e2-micro`, Ubuntu LTS, deployment-specific network/subnet, `10.10.0.0/24`, ephemeral external IPv4, and SSH tag/firewall configuration.
• The completion file’s location and exact content, resolved through noninteractive `gcloud compute ssh` without assuming a fixed username.

Validators accept `param([string]$projectname)`, use `gcloud` and JSON parsing, return the required response shape, and revoke gcloud authentication during cleanup.

The questions assess configuration recognition, external-IP/TCP/22 connectivity reasoning, and correct Linux home-directory file placement.

## Getting Started

1. Connect to the provisioned Windows `labvm` through CloudLabs RDP.
2. Open Microsoft Edge using the desktop shortcut to `https://console.cloud.google.com`.
3. Confirm that the CloudLabs-provided GCP project is selected. Deployment outputs provide the deployment-specific network and subnet names.
4. Complete Exercise 1 in the console, then use PowerShell on `labvm` for Exercise 2.
5. Allow time for SSH key propagation after the first connection request. If SSH is unavailable, verify that the VM is running, the ephemeral external IP is present, the expected network tag is attached, and the TCP/22 firewall rule is ready.

## GCP Documentation Sources

The fixed values and workflow are aligned with the following Google Cloud documentation:

• Compute Engine instance creation and configuration: https://cloud.google.com/compute/docs/instances/create-start-instance
• Compute Engine machine types, including the e2 series: https://cloud.google.com/compute/docs/general-purpose-machines
• Ubuntu images available for Compute Engine: https://cloud.google.com/compute/docs/images/os-details
• VPC firewall rules and ingress source ranges: https://cloud.google.com/firewall/docs/firewalls
• `gcloud compute ssh` connection workflow: https://cloud.google.com/sdk/gcloud/reference/compute/ssh
• Deployment Manager YAML deployments: https://cloud.google.com/deployment-manager/docs/deployments

These sources document the underlying GCP concepts; the lab’s resource names, zone, CIDR, machine type, SSH scope, and completion text remain the fixed assessment values listed above.