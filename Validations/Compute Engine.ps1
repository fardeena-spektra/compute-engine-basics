using namespace System.Net

param(
    [string]$projectname
)

# Google Cloud documentation:
# https://cloud.google.com/sdk/gcloud/reference/compute/instances/list
# https://cloud.google.com/sdk/gcloud/reference/topic/formats

function Write-ValidationResponse {
    param(
        [ValidateSet("Succeeded", "Failed")]
        [string]$Status,
        [string]$Message
    )

    $responseBody = @{ Status = $Status; Message = $Message } | ConvertTo-Json -Compress
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $responseBody
    })
}

$found = $false
$count = 0
$lastDiagnostic = "No validation attempt completed."

try {
    if ([string]::IsNullOrWhiteSpace($projectname)) {
        throw "The projectname parameter was empty."
    }

    $configOutput = & gcloud config set project $projectname 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Unable to set the active gcloud project to '$projectname': $($configOutput -join ' ')"
    }
    Write-Host "Project: $projectname"
    # Record platform context for server-side diagnostics without affecting validation.
    Write-Host "Platform context: subscription '$sub'; deployment '$DID'."

    do {
        $count++
        try {
            # --zones scopes the JSON listing to the required zone. The JSON
            # resource fields include name, zone, and status.
            $instancesJson = & gcloud compute instances list `
                --project=$projectname `
                --zones=us-central1-a `
                --format="json" 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "gcloud list failed: $($instancesJson -join ' ')"
            }

            $instancesText = $instancesJson -join [Environment]::NewLine
            $instances = if ([string]::IsNullOrWhiteSpace($instancesText)) {
                @()
            } else {
                @($instancesText | ConvertFrom-Json)
            }
            if ($null -eq $instances) {
                $instances = @()
            }

            $allDiscovered = @($instances | ForEach-Object {
                $zoneValue = [string]$_.zone
                if ($zoneValue -match '/([^/]+)$') {
                    $zoneValue = $Matches[1]
                }
                [pscustomobject]@{
                    Name   = [string]$_.name
                    Zone   = $zoneValue
                    Status = [string]$_.status
                }
            })
            $required = @($allDiscovered | Where-Object {
                $_.Name -eq "ubuntu-vm" -and $_.Zone -eq "us-central1-a"
            })

            $diagnostic = if ($allDiscovered.Count -eq 0) {
                "No instances were discovered in zone us-central1-a."
            } else {
                "Discovered instances: " + (($allDiscovered | ForEach-Object {
                    "$($_.Name) [$($_.Zone), $($_.Status)]"
                }) -join "; ")
            }
            $lastDiagnostic = $diagnostic

            if ($required.Count -eq 1 -and $required[0].Status -eq "RUNNING") {
                $found = $true
                $successMessage = "VM 'ubuntu-vm' is RUNNING in zone us-central1-a in project '$projectname'. $diagnostic"
                $successBody = @{ Status = "Succeeded"; Message = $successMessage } | ConvertTo-Json -Compress
                Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
                    StatusCode = [HttpStatusCode]::OK
                    Body       = $successBody
                })
            }
        }
        catch {
            $lastDiagnostic = $_.Exception.Message
        }

        if (-not $found -and $count -lt 3) {
            Start-Sleep -Seconds 10
        }
    } while ($count -lt 3 -and -not $found)

    if (-not $found) {
        if ($lastDiagnostic -like "gcloud list failed:*") {
            $failureMessage = "Unable to verify VM 'ubuntu-vm' in project '$projectname' after $count attempt(s): $lastDiagnostic"
        } else {
            $failureMessage = "VM 'ubuntu-vm' was not found RUNNING in zone us-central1-a in project '$projectname' after $count attempt(s). $lastDiagnostic"
        }
        $failureBody = @{ Status = "Failed"; Message = $failureMessage } | ConvertTo-Json -Compress
        Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
            StatusCode = [HttpStatusCode]::OK
            Body       = $failureBody
        })
    }
}
catch {
    $catchBody = @{ Status = "Failed"; Message = "Validation error for project '$projectname': $($_.Exception.Message)" } | ConvertTo-Json -Compress
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $catchBody
    })
}
finally {
    # Always revoke credentials when server-side validation finishes.
    & gcloud auth revoke --all 2>$null | Out-Null
}
