# Exercise 2: Connect with gcloud SSH and create the completion file

### Estimated Duration

40 minutes

## Overview

In this exercise, you connect from the Windows lab VM (`labvm`) to the learner-created Linux Compute Engine VM, `ubuntu-vm`. You will use PowerShell and `gcloud compute ssh`, confirm the remote default user's home directory, create `scenario2.txt`, and verify that the file contains exactly:

```text
scenario 2 is completed
```

The SSH firewall rule and the VM's ephemeral external IPv4 address are provided for this lab. Allowing TCP port 22 from the internet is intentionally simplified **lab-only access**; do not use this design for a production VM.

Your CloudLabs deployment ID is <inject key="DeploymentID"></inject>. The project used by this exercise is <inject key="projectId"></inject>.

## Sign in and open the lab VM

1. Sign in to the CloudLabs environment and open the Windows VM named `labvm` through RDP.
2. If you need to sign in to the Google Cloud console, open Microsoft Edge from the desktop shortcut and go to <https://console.cloud.google.com>. Use the credentials supplied for this lab:
   - Email: <inject key="GcpUserEmail"></inject>
   - Password: <inject key="GcpUserPassword"></inject>
3. In the Google Cloud console, select project <inject key="projectId"></inject>. Leave the console available so you can review the `ubuntu-vm` external IP and status if SSH troubleshooting is needed.
4. On `labvm`, open **PowerShell**. Confirm that `gcloud` is installed and set the active project to the lab-provided project:

```powershell
gcloud --version
gcloud auth list
gcloud config set project PROJECT_ID
gcloud config get-value project
```

Replace `PROJECT_ID` in the command with the project ID displayed above. The final command should print the provided project ID. If `gcloud auth list` does not show an authenticated account, run gcloud auth login and sign in with the lab GCP account shown above before continuing.

## Task 1: Connect to `ubuntu-vm` with gcloud SSH

1. From PowerShell on `labvm`, run the following command. The explicit zone prevents gcloud from asking you to choose a zone. The active project was set in the previous task, so no project flag is needed:

```powershell
gcloud compute ssh ubuntu-vm --zone=us-central1-a
```

2. On the first connection, follow the prompts to create or use the local Google Compute Engine SSH key. Accept the host-key prompt when the host is the expected `ubuntu-vm` instance.
3. After the prompt changes to the Linux shell, verify that you are on the correct VM and identify the account and home directory without hard-coding a username:

```bash
hostname
whoami
echo "$HOME"
printf 'Connected user: %s\nHome directory: %s\n' "$(whoami)" "$HOME"
```

The value printed by `$HOME` is the default user's home directory for this SSH session. Keep this terminal open; the next task is performed inside this session.

## Task 2: Create the required completion file

1. Create the file in the current user's home directory. Using `$HOME` ensures that the path follows the account selected by gcloud rather than assuming a fixed username:

```bash
printf '%s\n' 'scenario 2 is completed' > "$HOME/scenario2.txt"
```

2. Verify the filename, absolute location, and exact content:

```bash
find "$HOME" -maxdepth 1 -type f -name 'scenario2.txt' -print
realpath "$HOME/scenario2.txt"
printf 'Content: ['
cat "$HOME/scenario2.txt"
printf ']\n'
```

The output must show a path ending in `/scenario2.txt`, and the content between the brackets must be `scenario 2 is completed` followed by the normal line ending. Do not add quotation marks or extra text to the file.

3. Confirm that the file is readable and contains one line with the expected text:

```bash
wc -l "$HOME/scenario2.txt"
test "$(cat "$HOME/scenario2.txt")" = 'scenario 2 is completed' && echo 'Completion file verified.'
```

4. Exit the Linux session and return to PowerShell:

```bash
exit
```

The completion artifact is now in the home directory reported by `whoami` and `$HOME`; the guide intentionally does not assume a username.

<validation step="33ebd7b5-b3fc-4ede-b04c-d90b7ab88bc8" />

## Troubleshooting SSH readiness

### `gcloud compute ssh` cannot connect or times out

1. In the Google Cloud console, open **Compute Engine > VM instances**, select `ubuntu-vm`, and confirm that its zone is `us-central1-a` and its status is **Running**.
2. On the VM details page, confirm that an **External IPv4 address** is present. This exercise uses the normal external-IP SSH path from `labvm`; do not add `--internal-ip`.
3. If the VM is running and the external IP is present, retry after a short wait for guest startup and firewall programming to complete. From PowerShell, the supported diagnostic form is:

```powershell
gcloud compute ssh ubuntu-vm --zone=us-central1-a --troubleshoot
```

The `--troubleshoot` option checks common VM, network, permission, VPC, and boot causes. Do not create a second firewall rule in this lab.

### The command asks to create an SSH key or the key is not yet accepted

Allow gcloud to generate or use its default SSH key when prompted. `gcloud compute ssh` manages the public key needed by the VM. If a key was just generated or updated, wait briefly and retry so the key can propagate to the instance. If the local key files are damaged, follow the prompt or use the documented `--force-key-file-overwrite` option only when you understand that it replaces the affected key files.

### Permission or project errors appear

Run the following in PowerShell and verify the selected project before retrying:

```powershell
gcloud auth list
gcloud config get-value project
gcloud compute instances describe ubuntu-vm --zone=us-central1-a --format="value(status)"
```

The active identity must have access to the provided project and the VM must report `RUNNING`. Do not change the VM name or zone.

## Completion checklist

- [ ] Connected from PowerShell on `labvm` using `gcloud compute ssh ubuntu-vm --zone=us-central1-a`.
- [ ] Verified the remote account with `whoami` and its home directory with `$HOME`.
- [ ] Created `$HOME/scenario2.txt` with exact content `scenario 2 is completed`.
- [ ] Verified the filename, location, line count, and content.
- [ ] Exited the SSH session.

<question source="../../Inline-Questions/question-02.md" />
<question source="../../Inline-Questions/question-03.md" />
