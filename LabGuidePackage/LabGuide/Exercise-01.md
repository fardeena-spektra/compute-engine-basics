# Exercise 1: Create the Linux Compute Engine VM

### Estimated Duration

40 minutes

## Overview

In this exercise, you create the assessed Linux virtual machine in the Google Cloud console. You will use the lab-provisioned VPC network and subnet, configure the VM for the lab SSH workflow, start the VM, and verify its identity and key settings.

The VM you create must have these values:

| Setting | Required value |
|---|---|
| Instance name | `ubuntu-vm` |
| Zone | `us-central1-a` |
| Machine type | `e2-micro` |
| Boot image | Latest Ubuntu LTS image available in the console |
| Network | Deployment-specific lab VPC network shown in your lab outputs |
| Subnet | Deployment-specific subnet in `us-central1`, with CIDR `10.10.0.0/24` |
| External IPv4 address | Ephemeral |
| Network tag | The SSH tag shown in your lab outputs; it must match the pre-provisioned TCP/22 firewall rule |
| State after creation | Running |

The network and firewall dependencies are already provisioned. Do not create a second network or firewall rule in this exercise.

> **Lab-only networking note:** The pre-provisioned SSH rule permits TCP port 22 from the internet so that the Windows lab VM can use `gcloud compute ssh` in Exercise 2. This intentionally simplified exposure is for this disposable lab only; production environments should restrict SSH sources and use stronger access controls.

## Task 1: Sign in and confirm the project

1. On the Windows `labvm`, open Microsoft Edge using the desktop shortcut for the Google Cloud console, or open <https://console.cloud.google.com>.
2. Sign in with the provided training account:
   - Email: <inject key="GcpUserEmail"></inject>
   - Password: <inject key="GcpUserPassword"></inject>
3. In the project selector at the top of the console, select project <inject key="GcpProjectId"></inject>.
4. Confirm that the CloudLabs deployment identifier is <inject key="DeploymentID" enableCopy="false"></inject>.
5. Verify that the selected project is the provided lab project before creating any resource. If the console shows a different project, use the project selector again.

## Task 2: Open the VM creation page

1. Open the navigation menu, select **Compute Engine**, and select **VM instances**.
2. Select **Create instance**.
3. If Compute Engine asks you to enable an API, enable it and wait for the VM creation page to become available. Do not change the selected project.
4. In the **Name** field, enter `ubuntu-vm`.
5. In **Region and zone**, select region `us-central1` and zone `us-central1-a`.

## Task 3: Configure the machine and Ubuntu boot disk

1. In **Machine configuration**, select the general-purpose series and choose machine type `e2-micro`.
2. In **Boot disk**, select **Change**.
3. Choose the Ubuntu public image project and select the latest Ubuntu LTS image family/version currently offered by the console. Do not choose Debian, Windows, or an older non-LTS image.
4. Keep the boot disk as the default boot device unless the lab environment requires another default. Select **Select** to return to the VM creation page.

> **Image verification:** The console can present a versioned image from the Ubuntu LTS family. The requirement is the latest Ubuntu LTS available when you perform the exercise, not a hard-coded version string. Record the image family/version shown in the final instance details for your verification.

## Task 4: Configure the deployment network, ephemeral IP, and SSH tag

1. Expand **Advanced options**, then expand **Networking** if those sections are collapsed.
2. In the network interface configuration, select the deployment-specific lab VPC network and its subnet in `us-central1`. Use the exact network and subnet values exposed in the CloudLabs deployment outputs for deployment <inject key="DeploymentID" enableCopy="false"></inject>; do not substitute `default` or invent a name.
3. Confirm that the selected subnet has the lab CIDR `10.10.0.0/24`.
4. For **External IPv4 address**, leave or select **Ephemeral**. Do not reserve or attach a static address.
5. In **Network tags**, enter the SSH tag supplied by the deployment outputs. Use the exact tag expected by the pre-provisioned TCP/22 firewall rule, and do not add unrelated tags.
6. Review the remaining settings. Leave the VM configured to start normally after creation; do not select an option that prevents the instance from starting.

## Task 5: Create and verify `ubuntu-vm`

1. Select **Create**.
2. Wait for the new `ubuntu-vm` row to appear in **VM instances** and for its status to show **Running**. Refresh the page if necessary.
3. Select `ubuntu-vm` and review **Instance details**. Verify all of the following:
   - The name is exactly `ubuntu-vm`.
   - The zone is `us-central1-a`.
   - The machine type is `e2-micro`.
   - The boot disk shows the selected Ubuntu LTS image.
   - The network interface uses the deployment-specific VPC and subnet.
   - The subnet is the `10.10.0.0/24` lab subnet.
   - The external IPv4 address is present and is ephemeral.
   - The network tags include the required SSH tag.
   - The VM status is **Running**.
4. Record the displayed external IPv4 address. You will use it as a connectivity reference in Exercise 2; do not convert it to a static address.
5. If any setting is wrong, stop before Exercise 2. Use **Edit** on the instance to correct the setting, then return to the instance details page and verify again.

![VM instance details placeholder](./media/exercise-01-vm-details.png)

<question>
Which configuration is the valid target for `ubuntu-vm`? Select the option containing zone `us-central1-a`, machine type `e2-micro`, the latest Ubuntu LTS image, the deployment-specific `us-central1` subnet with CIDR `10.10.0.0/24`, an ephemeral external IPv4 address, and the SSH network tag expected by the pre-provisioned TCP/22 rule.
</question>

<validation step="validation-01"/>

## Troubleshooting

- **The network or subnet is not listed:** Confirm that the project selector shows <inject key="GcpProjectId"></inject>. If it is correct, return to the CloudLabs deployment outputs and use the exact network and subnet identifiers provided there; do not use the default network.
- **The VM does not become Running:** Wait for the creation operation to finish, refresh **VM instances**, and inspect the operation or instance error message. A VM that is stopped or suspended does not meet this exercise's requirement.
- **No external IPv4 address appears:** Edit the network interface and select an **Ephemeral** external IPv4 address, then save and verify the instance details again. Do not reserve a static address.
- **SSH tag or firewall readiness is uncertain:** Check the exact SSH tag in the deployment outputs and the VM's **Network tags** field. The firewall dependency is pre-provisioned; do not create a duplicate rule.

## Sources

The console choices and verification model in this exercise are aligned with the Google Cloud documentation surfaced through the documentation reference:

- [Create and configure a Compute Engine VM](https://docs.cloud.google.com/apigee/docs/api-platform/get-started/accessing-internal-proxies) — machine type, zone, subnet, image, and network tag fields used by Compute Engine VM creation.
- [Google Cloud documentation samples](https://docs.cloud.google.com/docs/samples) — Compute Engine image-family/version behavior and VM configuration examples.
- [Google Cloud firewall documentation](https://docs.cloud.google.com/firewall/docs) — firewall rules and tag-scoped traffic behavior.
