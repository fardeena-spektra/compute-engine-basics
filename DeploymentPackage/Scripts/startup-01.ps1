param(
    [string]$AzureUserName,
    [string]$AzurePassword
)

# CloudLabs Stage 1 Windows lab VM startup script.
# Runs as LocalSystem during Compute Engine startup and is safe to run again.

[Net.ServicePointManager]::SecurityProtocol = 'tls12, tls11, tls'
$ErrorActionPreference = 'Continue'
$LogDirectory = 'C:\ProgramData\CloudLabs'
$LogFile = Join-Path $LogDirectory 'cloudlabs-bootstrap.log'
New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null

function Write-BootstrapLog {
    param([AllowEmptyString()][string]$Message)
    $Line = "[{0}] {1}" -f (Get-Date -Format o), $Message
    Add-Content -LiteralPath $LogFile -Value $Line -Encoding UTF8
    Write-Output $Line
}

try {
    Start-Transcript -LiteralPath $LogFile -Append -ErrorAction SilentlyContinue | Out-Null
} catch {
    Write-BootstrapLog "Transcript could not be started: $($_.Exception.Message)"
}

Write-BootstrapLog 'CloudLabs Stage 1 bootstrap started.'

function Get-GceMetadata {
    param([Parameter(Mandatory = $true)][string]$Path)
    try {
        $Response = Invoke-RestMethod `
            -Headers @{ 'Metadata-Flavor' = 'Google' } `
            -Uri ("http://metadata.google.internal/computeMetadata/v1/{0}" -f $Path) `
            -TimeoutSec 10 `
            -ErrorAction Stop
        return [string]$Response
    } catch {
        Write-BootstrapLog "Metadata read failed for '$Path': $($_.Exception.Message)"
        return ''
    }
}

# Read deployment context from the canonical Compute Engine metadata server.
$ProjectId = Get-GceMetadata 'project/project-id'
$DeploymentId = Get-GceMetadata 'instance/attributes/deployment-id'
$LabVmName = Get-GceMetadata 'instance/name'
Write-BootstrapLog "Project=$ProjectId DeploymentId=$DeploymentId Instance=$LabVmName"

# Locate the lab-standard Google Cloud CLI installation and make it available now
# and to subsequent interactive PowerShell sessions.
$GcloudCandidates = @(
    (Join-Path ${env:ProgramFiles} 'Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd'),
    (Join-Path ${env:ProgramFiles} 'Google\Cloud SDK\google-cloud-sdk\bin\gcloud.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd'),
    (Join-Path ${env:ProgramFiles(x86)} 'Google\Cloud SDK\google-cloud-sdk\bin\gcloud.exe'),
    (Join-Path ${env:LOCALAPPDATA} 'Google\Cloud SDK\google-cloud-sdk\bin\gcloud.cmd'),
    (Join-Path ${env:LOCALAPPDATA} 'Google\Cloud SDK\google-cloud-sdk\bin\gcloud.exe')
)
$Gcloud = $GcloudCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $Gcloud) {
    $GcloudCommand = Get-Command gcloud.cmd -ErrorAction SilentlyContinue
    if (-not $GcloudCommand) { $GcloudCommand = Get-Command gcloud.exe -ErrorAction SilentlyContinue }
    if ($GcloudCommand) { $Gcloud = $GcloudCommand.Source }
}

$GcloudDirectory = ''
if ($Gcloud) {
    $GcloudDirectory = Split-Path -Parent $Gcloud
    $MachinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    if ($MachinePath -notlike "*$GcloudDirectory*") {
        [Environment]::SetEnvironmentVariable('Path', "$MachinePath;$GcloudDirectory", 'Machine')
    }
    $env:Path = "$GcloudDirectory;$env:Path"
    if ($ProjectId) {
        & $Gcloud config set project $ProjectId 2>&1 | ForEach-Object { Write-BootstrapLog ([string]$_) }
    }
    Write-BootstrapLog 'gcloud is available and the provided project is configured.'
} else {
    Write-BootstrapLog 'gcloud was not found; the lab-standard installation remains available for repair on first sign-in.'
}

# Create the non-admin local profile and a protected, non-secret context file.
$LabUser = 'labuser'
$LabHome = Join-Path $env:SystemDrive "Users\$LabUser"
if (-not (Get-LocalUser -Name $LabUser -ErrorAction SilentlyContinue)) {
    $Password = ConvertTo-SecureString (([Guid]::NewGuid().ToString('N')) + 'aA!') -AsPlainText -Force
    New-LocalUser -Name $LabUser -Password $Password -Description 'CloudLabs lab user' -PasswordNeverExpires -UserMayNotChangePassword | Out-Null
}
New-Item -ItemType Directory -Path $LabHome -Force | Out-Null
$CredsFile = Join-Path $LabHome 'cloudlabs-creds.env'
@(
    "PROJECT_ID=$ProjectId"
    "DEPLOYMENT_ID=$DeploymentId"
    "LAB_VM_NAME=$LabVmName"
) | Set-Content -LiteralPath $CredsFile -Encoding ASCII

try {
    $Acl = Get-Acl -LiteralPath $CredsFile
    $Acl.SetAccessRuleProtection($true, $false)
    $Acl.Access | ForEach-Object { $Acl.RemoveAccessRule($_) | Out-Null }
    $Acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        "$env:COMPUTERNAME\$LabUser", 'Read', 'Allow')))
    $Acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        'SYSTEM', 'FullControl', 'Allow')))
    Set-Acl -LiteralPath $CredsFile -AclObject $Acl
} catch {
    Write-BootstrapLog "Could not apply credentials-file ACL: $($_.Exception.Message)"
}

# Put a Microsoft Edge shortcut on the desktop shared by all users.
$PublicDesktop = Join-Path $env:PUBLIC 'Desktop'
New-Item -ItemType Directory -Path $PublicDesktop -Force | Out-Null
$EdgeCandidates = @(
    (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe'),
    (Join-Path ${env:ProgramFiles} 'Microsoft\Edge\Application\msedge.exe')
)
$Edge = $EdgeCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
$ShortcutPath = Join-Path $PublicDesktop 'Google Cloud Console.lnk'
if ($Edge) {
    $Shell = New-Object -ComObject WScript.Shell
    $Shortcut = $Shell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = $Edge
    $Shortcut.Arguments = 'https://console.cloud.google.com'
    $Shortcut.WorkingDirectory = Split-Path -Parent $Edge
    $Shortcut.IconLocation = "$Edge,0"
    $Shortcut.Save()
    Write-BootstrapLog 'Created the all-users Microsoft Edge shortcut to the Google Cloud console.'
} else {
    $UrlShortcut = Join-Path $PublicDesktop 'Google Cloud Console.url'
    @('[InternetShortcut]', 'URL=https://console.cloud.google.com', 'IconIndex=0', '') |
        Set-Content -LiteralPath $UrlShortcut -Encoding ASCII
    Write-BootstrapLog 'Microsoft Edge was not found; created an all-users browser URL shortcut instead.'
}

# Persist the CLI path for interactive PowerShell users when gcloud was found.
if ($GcloudDirectory) {
    $AllUsersProfile = Join-Path $PSHOME 'Profile.ps1'
    if (-not (Test-Path -LiteralPath $AllUsersProfile) -or
        -not (Select-String -LiteralPath $AllUsersProfile -SimpleMatch 'google-cloud-sdk' -Quiet -ErrorAction SilentlyContinue)) {
        Add-Content -LiteralPath $AllUsersProfile -Value ("`$env:Path = '{0};' + `$env:Path" -f $GcloudDirectory)
    }
}
Write-BootstrapLog 'PowerShell profile and bootstrap readiness completed.'
Write-BootstrapLog 'CloudLabs Stage 1 bootstrap finished.'
try { Stop-Transcript | Out-Null } catch { }
exit 0
