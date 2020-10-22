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

. (Join-Path $PSScriptRoot 'utilities.ps1')

# if there are any reboots pending then don't do anything. The odds are we'll get rebooted
# shortly so we just wait till that is no longer the case
$rebootResult = Test-PendingReboot -Detailed
Write-Output "A reboot is pending: $($rebootResult.IsRebootPending)"
if ($rebootResult.IsRebootPending)
{
    Write-Output "Windows update requires reboot: $($rebootResult.WindowsUpdateAutoUpdate)"
    Write-Output "Domain join requires reboot: $($rebootResult.PendingComputerRenameDomainJoin)"
    Write-Output "File rename requires reboot: $($rebootResult.PendingFileRenameOperations)"
    Write-Output "System center requires reboot: $($rebootResult.SystemCenterConfigManager)"

    # Wait 30 seconds so that we don't restart the service constantly
    Start-Sleep -Seconds 30

    # A reboot is pending. Just give up
    exit
}

try
{
    # Find the CD
    $dvdDriveLetter = Find-DvdDriveLetter @commonParameterSwitches
    if (($null -eq $dvdDriveLetter) -or ($dvdDriveLetter -eq ''))
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

    # If the allow WinRM file is not there, disable powershell remoting and WinRM
    # see: https://4sysops.com/wiki/disable-powershell-remoting-disable-psremoting-winrm-listener-firewall-and-localaccounttokenfilterpolicy/
    if (-not (Test-Path (Join-Path $dvdDriveLetter 'allow_winrm.json')))
    {
        # Disable powershell remoting
        Disable-PSRemoting -Force

        # Delete the winrm listeners
        & winrm delete winrm/config/listener?address=*+transport=HTTP

        # Stop the WinRM service and disable it
        Stop-Service WinRM -PassThru | Set-Service WinRM -StartupType Disabled -PassThru

        # Tell the firewall to not let anything through
        Set-NetFirewallRule -DisplayName 'Windows Remote Management (HTTP-In)' -Enabled False -PassThru | Select-Object -Property DisplayName, Profile, Enabled

        # More preventing remote powershell
        Set-ItemProperty -Path HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\policies\system -Name LocalAccountTokenFilterPolicy -Value 0
    }

    Set-NetworkLocation @commonParameterSwitches

    Initialize-Consul -dvdDriveLetter $dvdDriveLetter @commonParameterSwitches
    Initialize-Unbound -dvdDriveLetter $dvdDriveLetter @commonParameterSwitches
    Initialize-ConsulTemplate -dvdDriveLetter $dvdDriveLetter @commonParameterSwitches

    $customProvisioningScript = Join-Path $PSScriptRoot 'Initialize-CustomResource.ps1'
    if (Test-Path $customProvisioningScript)
    {
        . $customProvisioningScript
        Initialize-CustomResource
    }

    Disable-ProvisioningService @commonParameterSwitches

    Restart-Computer -ComputerName . -Force
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
