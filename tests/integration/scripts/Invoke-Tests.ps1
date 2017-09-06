[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

# Disable the progress stream because the WinRM feed doesn't like it.
$global:progresspreference = 'SilentlyContinue'

function Find-DvdDrive
{
    [CmdletBinding()]
    param(
    )

    $ErrorActionPreference = 'Stop'

    try
    {
        $drive = Get-WMIObject -Class Win32_CDROMDrive -ErrorAction Stop | Select-Object -First 1
        return $drive.Drive
    }
    catch
    {
        Continue;
    }

    return ''
}

$dvdDrive = Find-DvdDrive
if ($dvdDrive -eq '')
{
    Write-Output 'Could not locate the DVD drive.'
    exit -1
}

$result = Invoke-Pester -Script "$($dvdDrive)/pester/*" -PassThru

exit $result.FailedCount