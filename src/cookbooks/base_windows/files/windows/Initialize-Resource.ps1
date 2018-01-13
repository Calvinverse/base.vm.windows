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
        throw 'No DVD drive found'
    }

    # Only run the provisioning steps if we are asked to do so
    if (-not (Test-Path (Join-Path $dvdDriveLetter 'run_provisioning.json')))
    {
        # Not provisioning
        return
    }

    Set-HostName

    # If the allow WinRM file is not there, disable WinRM in the firewall
    if (-not (Test-Path (Join-Path $dvdDriveLetter 'allow_winrm.json')))
    {
        # Disable WinRM in the firewall
    }

    Initialize-Consul -dvdDriveLetter $dvdDriveLetter @commonParameterSwitches
    Initialize-ConsulTemplate -dvdDriveLetter $dvdDriveLetter @commonParameterSwitches
    Initialize-Unbound -dvdDriveLetter $dvdDriveLetter @commonParameterSwitches

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
