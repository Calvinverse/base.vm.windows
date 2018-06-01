[CmdletBinding()]
param(
    [string] $isoFilePath,

    [string] $outputIsoPath,

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

# Install the module if it is not installed for the current user
$latestUpdateModule = 'LatestUpdate'

# Install the module if it doesn't exist and otherwise make sure it is up to date
Install-Module -Name $latestUpdateModule -Force -Scope CurrentUser @commonParameterSwitches

# Import the module in the current scope
Import-Module -Name $latestUpdateModule @commonParameterSwitches

$workingPath = Join-Path $tempPath 'isoupdates'
try
{
    if (-not (Test-Path $workingPath))
    {
        New-Item -Path $workingPath -ItemType Directory | Out-Null
    }

    $updatesPath = Join-Path $workingPath 'updates'
    if (-not (Test-Path $updatesPath))
    {
        New-Item -Path $updatesPath -ItemType Directory | Out-Null
    }

    # Figure out what the current updates are
    # https://docs.microsoft.com/en-us/windows-server/get-started/windows-server-release-info
    # Currently we use Windows 2016 1709 (october 2017 release) which is build number 16299
    Write-Output 'Searching for update files ...'
    $updates = Get-LatestUpdate `
        -WindowsVersion Windows10 `
        -Build 14393 `
        -Architecture x64 `
        @commonParameterSwitches
    Write-Output "Found $($updates.Length) updates."

    Write-Output 'Downloading update files ...'
    Save-LatestUpdate `
        -Updates $updates `
        -Path $updatesPath
    Write-Output "Downloaded $($updates.Length) updates."

    # Now load the ISO and then patch it
    # From here: https://gist.github.com/PatrickLang/f8f3486cbbb49e0bb3f9c97e491c3981

    # Mount the installer ISO
    Write-Output 'Mounting ISO file ...'
    Mount-DiskImage $isoFilePath @commonParameterSwitches

    # Figure out which drive the ISO got mounted to
    $volume = get-volume | Where-Object FileSystem -eq UDF

    Write-Output "ISO file mounted at $($volume)"

    # Make directories to put the original files and the new files in
    $originalIsoFilePath = Join-Path $workingPath 'iso_contents'
    if (-not (Test-Path $originalIsoFilePath))
    {
        New-Item -Path $originalIsoFilePath -ItemType Directory | Out-Null
    }

    $updatedIsoFilePath = Join-Path $workingPath 'wim_unpacked'
    if (-not (Test-Path $updatedIsoFilePath))
    {
        New-Item -Path $updatedIsoFilePath -ItemType Directory | Out-Null
    }

    # Copy the contents of the ISO to the original directory
    robocopy /s /e "$($volume.DriveLetter):" $originalIsoFilePath

    # Dismount the original image. We don't need it anymore
    Write-Output 'Dismouting ISO file ...'
    Dismount-DiskImage $isoFilePath @commonParameterSwitches

    Write-Output 'ISO file dismounted'

    # Find the WIM file and make it writable
    Set-ItemProperty "$($originalIsoFilePath)\sources\install.wim" -Name IsReadOnly -Value $false

    Write-Output "Using DISM to mount the WIM file at: $($originalIsoFilePath)\sources\install.wim"
    dism.exe /mount-wim /wimfile:"$($originalIsoFilePath)\sources\install.wim" /mountdir:"$($updatedIsoFilePath)" /index:1

    try
    {
        try
        {
            Write-Output "Adding updates to the image ..."
            $updateFiles = Get-ChildItem -Path $updatesPath -Recurse -File
            foreach ($updateFile in $updateFiles)
            {
                Write-Output "Adding update in file $($updateFile.FullName) to the image ..."
                Write-Output "dism.exe /image:$updatedIsoFilePath /Add-Package /Packagepath:""$($updateFile.FullName)"""
                dism.exe /image:$updatedIsoFilePath /Add-Package /Packagepath:"$($updateFile.FullName)"
                if ($LastExitCode -ne 0)
                {
                    Write-Error "DISM failed with exit code: $($LastExitCode)"
                }

                Start-Sleep -Seconds 10
            }

            Write-Output "Updates Applied to WIM"

            dism.exe /image:"$($updatedIsoFilePath)" /cleanup-image /StartComponentCleanup /ResetBase
        }
        finally
        {
            dism.exe /unmount-image /mountdir:"$($updatedIsoFilePath)" /commit
        }

        $oscdimg = $adkPath + "Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe"
        $etfsboot = $adkPath + "Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\etfsboot.com"
        $efisys_noprompt = $adkPath + "Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\efisys_noprompt.bin"
        $parameters = "-bootdata:2#p0,e,b""$etfsboot""#pEF,e,b""$efisys_noprompt"" -u1 -udfver102 ""$originalIsoFilePath"" ""$outputIsoPath"""

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
        dism.exe /Cleanup-Wim
    }
}
finally
{
    if (Test-Path $workingPath)
    {
        #Remove-Item -Path $workingPath -Force -Recurse -ErrorAction SilentlyContinue
        Remove-Item -Path $originalIsoFilePath -Force -Recurse -ErrorAction SilentlyContinue
        Remove-Item -Path $updatedIsoFilePath -Force -Recurse -ErrorAction SilentlyContinue
    }
}
