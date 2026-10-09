#!/bin/bash
set -euo pipefail

# CloudLabs Stage 1 Windows labvm bootstrap.
# GCP references:
# - Windows startup scripts and metadata: https://cloud.google.com/compute/docs/instances/startup-scripts/windows
# - Compute Engine metadata server: https://cloud.google.com/compute/docs/metadata/overview
# - Google Cloud CLI on Windows: https://cloud.google.com/sdk/docs/install-sdk#windows
# - gcloud compute ssh: https://cloud.google.com/sdk/gcloud/reference/compute/ssh
#
# The deployment template should attach this payload as the instance startup-script
# metadata value through the lab's Windows bootstrap wrapper. The wrapper invokes
# the PowerShell block below on the Windows guest. The shell form is retained as
# the package's canonical startup artifact and is deliberately idempotent.

LOG_FILE="/var/log/cloudlabs-bootstrap.log"
if [ -d /var/log ]; then
  touch "$LOG_FILE" 2>/dev/null || true
  exec > >(tee -a "$LOG_FILE") 2>&1
fi

echo "[$(date -Is 2>/dev/null || date)] CloudLabs Stage 1 bootstrap started"

metadata_get() {
  local path="$1"
  curl -fsS --max-time 10 -H "Metadata-Flavor: Google" \
    "http://metadata.google.internal/computeMetadata/v1/${path}" 2>/dev/null || true
}

PROJECT_ID="$(metadata_get project/project-id)"
DEPLOYMENT_ID="$(metadata_get instance/attributes/deployment-id)"
LAB_VM_NAME="$(metadata_get instance/name)"

# This script is consumed by the Windows startup wrapper. On a Windows guest,
# powershell.exe is expected to be available; use it for all Windows-native work.
if command -v powershell.exe >/dev/null 2>&1; then
  powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command - <<'POWERSHELL'
$ErrorActionPreference = 'Continue'
$Log = 'C:\ProgramData\CloudLabs\cloudlabs-bootstrap.log'
New-Item -ItemType Directory -Force -Path (Split-Path $Log) | Out-Null
function Write-Log([string]$Text) {
  $line = "[$(Get-Date -Format o)] $Text"
  Add-Content -LiteralPath $Log -Value $line
  Write-Output $line
}

# Read canonical GCE context from the metadata server (Metadata-Flavor is required).
function Get-Metadata([string]$Path) {
  try {
    (Invoke-RestMethod -Headers @{'Metadata-Flavor'='Google'} -Uri "http://metadata.google.internal/computeMetadata/v1/$Path" -TimeoutSec 10).ToString()
  } catch { '' }
}
$ProjectId = Get-Metadata 'project/project-id'
$DeploymentId = Get-Metadata 'instance/attributes/deployment-id'
$LabVmName = Get-Metadata 'instance/name'
Write-Log "Project=$ProjectId DeploymentId=$DeploymentId Instance=$LabVmName"

# Keep the standard Windows PowerShell and modern PowerShell command locations available.
$GcloudCandidates = @(
  "$env:ProgramFiles\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd",
  "$env:ProgramFiles(x86)\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd",
  "$env:LOCALAPPDATA\Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd"
)
$Gcloud = $GcloudCandidates | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $Gcloud) { $Gcloud = (Get-Command gcloud.cmd -ErrorAction SilentlyContinue).Source }
if ($Gcloud) {
  $GcloudDir = Split-Path $Gcloud
  $MachinePath = [Environment]::GetEnvironmentVariable('Path','Machine')
  if ($MachinePath -notlike "*$GcloudDir*") {
    [Environment]::SetEnvironmentVariable('Path', "$MachinePath;$GcloudDir", 'Machine')
  }
  $env:Path = "$GcloudDir;$env:Path"
  if ($ProjectId) { & $Gcloud config set project $ProjectId 2>&1 | ForEach-Object { Write-Log $_ } }
  Write-Log 'gcloud is available and the provided project is configured.'
} else {
  Write-Log 'gcloud was not found; leaving the lab-standard installation intact for repair on first sign-in.'
}

# Create the non-admin lab profile used for local bootstrap artifacts if absent.
$LabUser = 'labuser'
$LabHome = "C:\Users\$LabUser"
if (-not (Get-LocalUser -Name $LabUser -ErrorAction SilentlyContinue)) {
  $Password = ConvertTo-SecureString ([Guid]::NewGuid().ToString('N') + 'aA!') -AsPlainText -Force
  New-LocalUser -Name $LabUser -Password $Password -Description 'CloudLabs lab user' -PasswordNeverExpires -UserMayNotChangePassword | Out-Null
}
New-Item -ItemType Directory -Force -Path $LabHome | Out-Null
$Creds = @("PROJECT_ID=$ProjectId", "DEPLOYMENT_ID=$DeploymentId", "LAB_VM_NAME=$LabVmName") -join "`n"
Set-Content -LiteralPath "$LabHome\cloudlabs-creds.env" -Value ($Creds + "`n") -Encoding ASCII
$Acl = Get-Acl "$LabHome\cloudlabs-creds.env"
$Acl.SetAccessRuleProtection($true,$false)
$Acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule("$env:COMPUTERNAME\$LabUser",'Read','Allow')))
Set-Acl -LiteralPath "$LabHome\cloudlabs-creds.env" -AclObject $Acl

# Create a browser shortcut on the all-users desktop so RDP users can launch the console.
$Desktop = "$env:PUBLIC\Desktop"
New-Item -ItemType Directory -Force -Path $Desktop | Out-Null
$Shortcut = Join-Path $Desktop 'Google Cloud Console.url'
Set-Content -LiteralPath $Shortcut -Encoding ASCII -Value @('[InternetShortcut]','URL=https://console.cloud.google.com','IconIndex=0','')
Write-Log 'Created Google Cloud Console Edge-compatible desktop shortcut.'

# Make PowerShell and gcloud convenient for every interactive Windows PowerShell session.
$ProfileDir = Split-Path $PROFILE.CurrentUserAllHosts
New-Item -ItemType Directory -Force -Path $ProfileDir | Out-Null
$ProfileLine = "`$env:Path = '$GcloudDir;' + `$env:Path"
if ($Gcloud -and -not (Select-String -LiteralPath $PROFILE.CurrentUserAllHosts -SimpleMatch 'google-cloud-sdk' -Quiet -ErrorAction SilentlyContinue)) {
  Add-Content -LiteralPath $PROFILE.CurrentUserAllHosts -Value $ProfileLine
}
Write-Log 'PowerShell profile and bootstrap readiness completed.'
POWERSHELL
else
  echo "powershell.exe is unavailable; this payload must be invoked by the Windows GCE startup-script wrapper."
fi

echo "[$(date -Is 2>/dev/null || date)] CloudLabs Stage 1 bootstrap finished"
exit 0
