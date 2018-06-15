<#
    .SYNOPSIS
        Prepares a Windows ISO file for use in unattended installs.

    .DESCRIPTION
        The script removings the prompt "Press any key to boot from CD/DVD" message, allowing fully unattended OSD by
        using an 'unattend.xml' file.

    .NOTES
        Original code from: https://scadminsblog.wordpress.com/2017/05/18/how-to-remove-the-message-press-any-key-to-boot-from-cd-or-dvd-with-powershell/

    .PARAMETER sourceIsoPath
        Path to the source ISO file; can be relative.

    .PARAMETER unattendedIsoPath
        Path to the destination ISO file; can be relative.

    .PARAMETER tempPath
        Path to the temp folder in which the ISO file is unpacked.

    .EXAMPLE
        .\Prepare-WindowsIsoForUnattendedInstall.ps1 `
            -sourceIsoPath "d:\temp\OSD.ISO" `
            -unattendedIsoPath "d:\temp\Unattended.ISO" `
            -tempPath "d:\temp\unpack"
#>
[CmdletBinding()]
Param (
    [Parameter(Mandatory = $true)]
    [ValidateScript({Test-Path $_ -PathType Leaf})]
    [string] $sourceIsoPath,

    [Parameter(Mandatory = $false)]
    [string] $unattendedIsoPath = '.\Unattended.ISO',

    [Parameter(Mandatory = $false)]
    [string] $tempPath = $env:TEMP
)

$ErrorActionPreference = 'Stop'

$commonParameterSwitches =
    @{
        Verbose = $PSBoundParameters.ContainsKey('Verbose');
        Debug = $false;
        ErrorAction = "Stop"
    }

# ---------------------------- Script functions --------------------------------

function Get-AdkPath
{
    $props = Get-ItemProperty -Path "HKLM:\Software\WOW6432Node\Microsoft\Windows Kits\Installed Roots" @commonParameterSwitches
    return $props.KitsRoot10
}

# ---------------------------- End script functions ----------------------------

Write-Output "Searching for the windows ADK ..."
$adkPath = Get-AdkPath
if (-not (Test-Path $adkPath))
{
    throw "Failed to find the ADK install path. Cannot continue"
}

# Then we create the parent folder of the output file, if it does not exist
if (!(Test-Path -Path (Split-Path -Path $unattendedIsoPath -Parent)))
{
    $newLocation = New-Item -Path (Split-Path -Path $unattendedIsoPath -Parent) -ItemType Directory -Force
    Write-Output "The parent folder of the output ISO file, $($newLocation.FullName) has been created."
}

# Then we start processing the source ISO file
$sourceIsoFullPath = (Get-Item -Path $sourceIsoPath).FullName
$isMounted = $false
try
{
    try
    {
        Mount-DiskImage -ImagePath $sourceIsoFullPath @commonParameterSwitches
        $isMounted = $true
    }
    catch
    {
        Write-Error 'An error occured while mounting the source ISO file. It may be corrupt. Aborting...'
        exit
    }

    $isoImage = Get-DiskImage -ImagePath $sourceIsoFullPath | Get-Volume
    $isoDrive = "$([string]$isoImage.DriveLetter):"

    # Test if we have enough memory on the current Windows drive to perform the operation (twice the size of the IS0)
    $isoItem = Get-Item -Path $sourceIsoFullPath
    $tempDrive = Get-WmiObject Win32_LogicalDisk -filter "deviceid=""$([System.IO.Path]::GetPathRoot($tempPath).Trim('\'))""" @commonParameterSwitches

    if (($isoItem.Length * 2) -le $tempDrive.FreeSpace)
    {
        Write-Output "The current drive ($($tempDrive)) appears to have enough free space ($($tempDrive.FreeSpace)) for the ISO conversion process ($(2 * $isoItem.Length))."
    }
    else
    {
        Write-Error "The current drive ($($tempDrive)) does not appear to have enough free space ($($tempDrive.FreeSpace)) for the ISO conversion process ($(2 * $isoItem.Length)). Aborting..."
        exit
    }

    # Process the ISO content using a temporary folder on the local system drive
    $targetPath = Join-Path $tempPath "sourceisotemp"
    if (!(Test-Path -Path $targetPath -PathType Container))
    {
        New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
    }
    else
    {
        Remove-Item -Path $targetPath -Force -Confirm:$false @commonParameterSwitches
        New-Item -Path $targetPath -ItemType Directory -Force | Out-Null
    }

    try
    {
        Write-Output "Extracting the content of the ISO file to $targetPath ..."
        Get-ChildItem -Path $isoDrive | Copy-Item -Destination $targetPath -Recurse -Container -Force

        Write-Output "The content of the ISO file has been extracted to $targetPath."

        # Remove the bootfix file that contains the instructions for manual installs and replace it with the
        # automatic install one
        Write-Output "Replacing the manual install 'bootfix.bin' file with the automatic install 'bootfix.bin' ... "

        $manualBootFile = Join-Path $targetPath "boot\bootfix.bin"
        if (Test-Path -Path $manualBootFile -PathType Leaf)
        {
            Remove-Item -Path $manualBootFile -Force -Confirm:$false @commonParameterSwitches
        }

        $oscdimg = $adkPath + "Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
        $etfsboot = $adkPath + "Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\etfsboot.com"
        $efisys_noprompt = $adkPath + "Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\efisys_noprompt.bin"
        $parameters = "-bootdata:2#p0,e,b""$etfsboot""#pEF,e,b""$efisys_noprompt"" -u1 -udfver102 ""$targetPath"" ""$unattendedIsoPath"""

        $processResult = Start-Process -FilePath $oscdimg -ArgumentList $parameters -Wait -NoNewWindow -PassThru @commonParameterSwitches

        if ($processResult.ExitCode -ne 0)
        {
            Write-Error "There was an error while creating the iso file."
        }
        else
        {
            Write-Output "The content of the ISO has been repackaged in the new ISO file."
        }
    }
    finally
    {
        Remove-Item -Path $targetPath -Force -Recurse -Confirm:$false @commonParameterSwitches
        Write-Output "The temp folder has been removed."
    }
}
finally
{
    Dismount-DiskImage -ImagePath $sourceIsoFullPath @commonParameterSwitches
    Write-Output "The source ISO file has been unmounted."
}
