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
$VmPassword = Get-GceMetadata 'instance/attributes/vm-password'
Write-BootstrapLog "Project=$ProjectId DeploymentId=$DeploymentId Instance=$LabVmName"

# Create or reset the local lab account using the password supplied through
# the Compute Engine instance metadata attribute. Do not write the password to logs.
if ($VmPassword) {
    try {
        $SecureVmPassword = ConvertTo-SecureString $VmPassword -AsPlainText -Force
        $LabUser = Get-LocalUser -Name 'labuser' -ErrorAction SilentlyContinue
        if ($LabUser) {
            Set-LocalUser -Name 'labuser' -Password $SecureVmPassword -ErrorAction Stop
            Write-BootstrapLog 'Reset the password for local user labuser.'
        } else {
            New-LocalUser -Name 'labuser' -Password $SecureVmPassword -AccountNeverExpires -PasswordNeverExpires -Description 'CloudLabs local lab user' -ErrorAction Stop | Out-Null
            Write-BootstrapLog 'Created local user labuser.'
        }
        Add-LocalGroupMember -Group 'Administrators' -Member 'labuser' -ErrorAction SilentlyContinue
        Add-LocalGroupMember -Group 'Remote Desktop Users' -Member 'labuser' -ErrorAction SilentlyContinue
        Write-BootstrapLog 'Ensured labuser is a member of Administrators and Remote Desktop Users.'
    } catch {
        Write-BootstrapLog "Local lab user configuration failed: $($_.Exception.Message)"
    }
} else {
    Write-BootstrapLog 'The vm-password metadata attribute was empty; local lab user configuration was skipped.'
}

# Enable Remote Desktop and its Windows Firewall rule group.
try {
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server' -Name 'fDenyTSConnections' -Value 0 -Type DWord -Force -ErrorAction Stop
    Enable-NetFirewallRule -DisplayGroup 'Remote Desktop' -ErrorAction Stop
    Write-BootstrapLog 'Enabled Remote Desktop and the Windows Firewall Remote Desktop group.'
} catch {
    Write-BootstrapLog "Remote Desktop configuration failed: $($_.Exception.Message)"
}

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

if (-not $Gcloud) {
    $InstallerPath = Join-Path $env:TEMP 'GoogleCloudSDKInstaller.exe'
    try {
        Invoke-WebRequest -Uri 'https://dl.google.com/dl/cloudsdk/channels/rapid/GoogleCloudSDKInstaller.exe' -OutFile $InstallerPath -UseBasicParsing -ErrorAction Stop
        Start-Process -FilePath $InstallerPath -ArgumentList '/S', '/allusers', '/noreporting' -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue | Out-Null
    } catch {
        Write-BootstrapLog "gcloud installation failed: $($_.Exception.Message)"
    }
    $Gcloud = $GcloudCandidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if (-not $Gcloud) {
        $GcloudCommand = Get-Command gcloud.cmd -ErrorAction SilentlyContinue
        if (-not $GcloudCommand) { $GcloudCommand = Get-Command gcloud.exe -ErrorAction SilentlyContinue }
        if ($GcloudCommand) { $Gcloud = $GcloudCommand.Source }
    }
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
    Write-BootstrapLog 'gcloud was not found and could not be installed.'
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
