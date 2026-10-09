param([string]$projectname)

using namespace System.Net

# Validation 2: learner-created ubuntu-vm configuration.
# Google Cloud references:
# https://cloud.google.com/sdk/gcloud/reference/compute/instances/describe
# https://cloud.google.com/sdk/gcloud/reference/compute/subnetworks/list
# https://cloud.google.com/sdk/gcloud/reference/compute/firewall-rules/list
# https://cloud.google.com/compute/docs/images/os-details

function Send-ValidationResponse {
    param(
        [ValidateSet('Succeeded', 'Failed')][string]$Status,
        [string]$Message
    )
    if ($Status -eq 'Succeeded') {
        $body = @{ Status = "Succeeded"; Message = $Message } | ConvertTo-Json -Compress
    }
    else {
        $body = @{ Status = "Failed"; Message = $Message } | ConvertTo-Json -Compress
    }
    Push-OutputBinding -Name Response -Value ([HttpResponseContext]@{
        StatusCode = [HttpStatusCode]::OK
        Body       = $body
    })
}

function Get-JsonFromGcloud {
    param([string[]]$Arguments)
    $raw = & gcloud @Arguments --format="json" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ("gcloud {0} failed: {1}" -f ($Arguments -join ' '), ($raw -join ' '))
    }
    if ([string]::IsNullOrWhiteSpace(($raw -join ''))) { return @() }
    return ($raw -join "`n") | ConvertFrom-Json
}

# The platform may expose subscription/deployment context under these names; GCP checks use projectname.
$platformSubscription = [string]$sub
$deploymentId = [string]$DID
$count = 0
$found = $false

try {
    if ([string]::IsNullOrWhiteSpace($projectname)) { throw 'The projectname parameter was empty.' }
    $configOutput = & gcloud config set project $projectname 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw ("Unable to select project '{0}': {1}" -f $projectname, ($configOutput -join ' '))
    }
    Write-Host "Project: $projectname"

    do {
        $count++
        $instances = @(Get-JsonFromGcloud @('compute','instances','list','--project',$projectname,'--filter=name=ubuntu-vm'))
        $vmMatches = @($instances | Where-Object { $_.name -eq 'ubuntu-vm' -and $_.zone -match '/zones/us-central1-a$' })
        if ($vmMatches.Count -eq 1) { $found = $true; break }
        if ($count -lt 3) { Start-Sleep -Seconds 10 }
    } while ($count -lt 3 -and -not $found)

    if ($vmMatches.Count -ne 1) {
        Send-ValidationResponse -Status Failed -Message ("Expected exactly one instance named 'ubuntu-vm' in zone us-central1-a; found {0}. Confirm the exact name and zone, then retry." -f $vmMatches.Count)
    }
    else {
        $vm = $vmMatches[0]
        $problems = [System.Collections.Generic.List[string]]::new()
        $details = [System.Collections.Generic.List[string]]::new()
        if ($vm.status -ne 'RUNNING') { [void]$problems.Add("instance status is '$($vm.status)' (expected RUNNING)") }
        if (-not ($vm.machineType -match '/machineTypes/e2-micro$')) { [void]$problems.Add("machine type is '$($vm.machineType)' (expected e2-micro)") }

        $boot = @($vm.disks | Where-Object { $_.boot -eq $true }) | Select-Object -First 1
        $sourceImage = if ($boot -and $boot.initializeParams) { [string]$boot.initializeParams.sourceImage } else { '' }
        if ($sourceImage -notmatch '/projects/ubuntu-os-cloud/' -or $sourceImage -notmatch '/images/ubuntu-') {
            [void]$problems.Add("boot source image '$sourceImage' is not an Ubuntu LTS image from ubuntu-os-cloud")
        }

        $interfaces = @($vm.networkInterfaces)
        if ($interfaces.Count -ne 1) { [void]$problems.Add("expected one network interface, found $($interfaces.Count)") }
        $nic = $interfaces | Select-Object -First 1
        $subnetworks = @(Get-JsonFromGcloud @('compute','networks','subnets','list','--project',$projectname,'--regions','us-central1'))
        $labSubnets = @($subnetworks | Where-Object { $_.ipCidrRange -eq '10.10.0.0/24' })
        if ($labSubnets.Count -ne 1) {
            [void]$problems.Add("expected exactly one us-central1 subnet with CIDR 10.10.0.0/24, found $($labSubnets.Count)")
        }
        else {
            $subnet = $labSubnets[0]
            $expectedNetwork = [string]$subnet.network
            if ([string]$nic.subnetwork -ne [string]$subnet.selfLink) { [void]$problems.Add("VM subnetwork '$($nic.subnetwork)' does not match lab subnet '$($subnet.name)'") }
            if ([string]$nic.network -ne $expectedNetwork) { [void]$problems.Add("VM network '$($nic.network)' does not match the lab subnet network") }
            [void]$details.Add("network=$($subnet.name); subnetCidr=$($subnet.ipCidrRange)")

            $vmTags = @($vm.tags.items)
            $firewalls = @(Get-JsonFromGcloud @('compute','firewall-rules','list','--project',$projectname))
            $sshRules = @($firewalls | Where-Object {
                [string]$_.network -eq $expectedNetwork -and @($_.sourceRanges) -contains '0.0.0.0/0' -and
                @($_.targetTags | Where-Object { $vmTags -contains $_ }).Count -gt 0 -and
                @($_.allowed | Where-Object { $_.IPProtocol -eq 'tcp' -and ((@($_.ports) -contains '22') -or (@($_.ports) -contains '22-22')) }).Count -gt 0
            })
            if ($sshRules.Count -eq 0) { [void]$problems.Add("no matching firewall rule allows tcp:22 from 0.0.0.0/0 to the VM's network tag(s) [$($vmTags -join ', ')]") }
            else { [void]$details.Add("sshFirewall=$($sshRules[0].name)") }
        }

        $access = @($nic.accessConfigs | Where-Object { $_.natIP })
        if ($access.Count -ne 1 -or $access[0].type -ne 'ONE_TO_ONE_NAT') {
            [void]$problems.Add('VM does not have exactly one external IPv4 ONE_TO_ONE_NAT access configuration')
        }
        else {
            $natIp = [string]$access[0].natIP
            $reserved = @(Get-JsonFromGcloud @('compute','addresses','list','--project',$projectname,'--regions','us-central1') | Where-Object { $_.address -eq $natIp })
            if ($reserved.Count -gt 0) { [void]$problems.Add("external IPv4 $natIp is reserved; use an ephemeral external IPv4") }
            else { [void]$details.Add("externalIPv4=$natIp (not in regional reserved-address inventory)") }
        }

        if ($problems.Count -eq 0) {
            Send-ValidationResponse -Status Succeeded -Message ("VM 'ubuntu-vm' in us-central1-a has e2-micro, Ubuntu LTS, the deployment lab subnet 10.10.0.0/24, an ephemeral external IPv4, and matching tcp:22 firewall reachability. Observed: {0}" -f ($details -join '; '))
        }
        else {
            Send-ValidationResponse -Status Failed -Message ("VM 'ubuntu-vm' configuration failed: {0}. Correct the listed Compute Engine, VPC subnet, external IP, tag, or firewall settings and rerun. Observed: {1}" -f ($problems -join '; '), ($details -join '; '))
        }
    }
}
catch {
    Send-ValidationResponse -Status Failed -Message ("Configuration validation failed for project '$projectname': $($_.Exception.Message). Confirm gcloud authentication, project access, and Compute Engine API availability, then retry.")
}
finally {
    gcloud auth revoke --all 2>$null
}
