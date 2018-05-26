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

# Copy the files from the DVD
$tempDir = 'c:\temp'
if (-not (Test-Path $tempDir))
{
    New-Item -Path $tempDir -ItemType Container | Out-Null
}

Copy-Item -Path "$($dvdDrive)/pester" -Destination $tempDir -Recurse

# Set the consul Key-Value pairs
. 'c:\temp\pester\consul\Initialize-Environment.ps1'
Initialize-Environment

# Invoke pester
$result = Invoke-Pester -Script 'c:\temp\pester\*' -PassThru

exit $result.FailedCount
