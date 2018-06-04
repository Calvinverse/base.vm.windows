<#
    .SYNOPSIS

    Configures the current resource.


    .DESCRIPTION
#>
[CmdletBinding()]
param(
)

$ErrorActionPreference = 'Stop'

$commonParameterSwitches =
    @{
        Verbose = $true;
        Debug = $false;
        ErrorAction = "Stop"
    }

. (Join-Path $PSScriptRoot 'Initialize.ps1')

try
{
    # Find the CD
    $dvdDriveLetter = Find-DvdDriveLetter @commonParameterSwitches
    if (($dvdDriveLetter -eq $null) -or ($dvdDriveLetter -eq ''))
    {
        Start-Sleep -Seconds 15
        Write-Output 'No DVD drive found'
        return
    }

    # Only run the provisioning steps if we are asked to do so
    if (-not (Test-Path (Join-Path $dvdDriveLetter 'run_provisioning.json')))
    {
        # Not provisioning
        return
    }

    Set-HostName @commonParameterSwitches

    # If the allow WinRM file is not there, disable WinRM in the firewall
    if (-not (Test-Path (Join-Path $dvdDriveLetter 'allow_winrm.json')))
    {
        # Disable WinRM in the firewall
    }

    Set-NetworkLocation @commonParameterSwitches

    Initialize-Consul -dvdDriveLetter $dvdDriveLetter @commonParameterSwitches
    Initialize-Unbound -dvdDriveLetter $dvdDriveLetter @commonParameterSwitches
    Initialize-ConsulTemplate -dvdDriveLetter $dvdDriveLetter @commonParameterSwitches

    Disable-ProvisioningService @commonParameterSwitches
}
catch
{
    $ErrorRecord=$Error[0]
    $ErrorRecord | Format-List * -Force
    $ErrorRecord.InvocationInfo |Format-List *
    $Exception = $ErrorRecord.Exception
    for ($i = 0; $Exception; $i++, ($Exception = $Exception.InnerException))
    {
        "$i" * 80
        $Exception |Format-List * -Force
    }
}
