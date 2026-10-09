param([string]$projectname)

using namespace System.Net

$instanceName = "ubuntu-vm"
$zone = "us-central1-a"
$expectedText = "scenario 2 is completed"
$expectedBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("$expectedText`n"))
$stderrFile = [IO.Path]::GetTempFileName()
$found = $false
$count = 0

function Send-Result {
    param([string]$Status, [string]$Message)
    if ($Status -eq "Succeeded") {
        $json = @{ Status = "Succeeded"; Message = $Message } | ConvertTo-Json -Compress
    } else {
        $json = @{ Status = "Failed"; Message = $Message } | ConvertTo-Json -Compress
    }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body = $json
    })
}

try {
    if ([string]::IsNullOrWhiteSpace($projectname)) {
        throw "The project name was not supplied by the platform."
    }

    # $sub and $DID are supplied by the CloudLabs function runtime.
    Write-Host "Deployment context: subscription=$sub deployment=$DID"
    gcloud config set project $projectname --quiet 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "gcloud could not select project '$projectname'."
    }
    Write-Host "Project: $projectname"

    $instances = & gcloud compute instances list --project $projectname --filter="name=$instanceName AND zone:($zone)" --format="json" 2>$stderrFile | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to list Compute Engine instances in project '$projectname'."
    }
    $target = @($instances | Where-Object { $_.name -eq $instanceName -and $_.zone -match "/zones/$zone$" })
    if ($target.Count -ne 1) {
        Send-Result -Status "Failed" -Message "Expected exactly one instance named '$instanceName' in zone '$zone', but found $($target.Count) in project '$projectname'."
        return
    }
    if ($target[0].status -ne "RUNNING") {
        Send-Result -Status "Failed" -Message "VM '$instanceName' was found in zone '$zone' but is '$($target[0].status)', not RUNNING; SSH validation cannot proceed."
        return
    }

    # --command executes remotely and exits. --quiet suppresses confirmation prompts. HOME is
    # resolved on the guest, so no Linux username is hard-coded.
    $remoteCommand = 'set -eu; home="${HOME:?}"; test -f "$home/scenario2.txt"; printf "__CL_HOME__=%s\n" "$home"; printf "__CL_CONTENT_B64__="; base64 "$home/scenario2.txt" | tr -d "\r\n"; printf "\n"'
    $sshOutput = $null
    $sshError = $null
    do {
        $count++
        $sshOutput = (& gcloud compute ssh $instanceName --project $projectname --zone $zone --quiet --command $remoteCommand 2>$stderrFile | Out-String)
        $sshExitCode = $LASTEXITCODE
        $sshError = (Get-Content -LiteralPath $stderrFile -Raw -ErrorAction SilentlyContinue)
        if ($sshExitCode -eq 0) {
            $found = $true
        } elseif ($count -lt 3) {
            Start-Sleep -Seconds 10
        }
    } while ($count -lt 3 -and -not $found)

    if (-not $found) {
        $detail = if ([string]::IsNullOrWhiteSpace($sshError)) { "No diagnostic text was returned." } else { ($sshError.Trim() -replace "\s+", " ") }
        Send-Result -Status "Failed" -Message "SSH inspection of '$instanceName' in zone '$zone' failed after $count attempt(s) (exit code $sshExitCode). Check TCP/22 reachability and SSH key propagation. Detail: $detail"
        return
    }

    $homeMatch = [regex]::Match($sshOutput, '(?m)^__CL_HOME__=(?<home>/[^\r\n]+)$')
    $contentMatch = [regex]::Match($sshOutput, '(?m)^__CL_CONTENT_B64__=(?<content>[A-Za-z0-9+/=]+)$')
    if (-not $homeMatch.Success -or -not $contentMatch.Success) {
        Send-Result -Status "Failed" -Message "SSH completed for '$instanceName', but the remote home-directory or scenario2.txt inspection markers were not returned."
        return
    }

    $remoteHome = $homeMatch.Groups["home"].Value
    $remoteBase64 = $contentMatch.Groups["content"].Value
    if ($remoteBase64 -ne $expectedBase64) {
        Send-Result -Status "Failed" -Message "File '$remoteHome/scenario2.txt' exists on VM '$instanceName', but its content is not exactly '$expectedText' followed by one line ending."
        return
    }

    Send-Result -Status "Succeeded" -Message "VM '$instanceName' in zone '$zone' contains '$remoteHome/scenario2.txt' with exact content '$expectedText' followed by a normal line ending."
}
catch {
    Send-Result -Status "Failed" -Message "Scenario 2 validation error for project '$projectname': $($_.Exception.Message)"
}
finally {
    if (Test-Path -LiteralPath $stderrFile) {
        Remove-Item -LiteralPath $stderrFile -Force -ErrorAction SilentlyContinue
    }
    gcloud auth revoke --all 2>$null | Out-Null
}
