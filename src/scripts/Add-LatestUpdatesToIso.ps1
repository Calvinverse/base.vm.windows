[CmdletBinding()]
param(
    [string] $isoFilePath,

    [string] $outputIsoPath,

    [string] $tempPath = $env:TEMP,

    # Figure out what the current updates are
    # https://docs.microsoft.com/en-us/windows-server/get-started/windows-server-release-info
    [int] $buildNumber = 17134
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

Write-Output "Found the windows ADK at: $adkPath"

Write-Output "Getting 'LastestUpdate' powershell module ..."

# Install the module if it is not installed for the current user
$latestUpdateModule = 'LatestUpdate'

# Install the module if it doesn't exist and otherwise make sure it is up to date
Install-Module -Name $latestUpdateModule -Scope CurrentUser -Force @commonParameterSwitches

# Import the module in the current scope
Import-Module -Name $latestUpdateModule @commonParameterSwitches

# Make sure the input path is an absolute path
if (-not ([System.IO.Path]::IsPathRooted($isoFilePath)))
{
    $isoFilePath = [System.IO.Path]::GetFullPath((Join-Path $pwd $isoFilePath))
}

# Make sure the output path is an absolute path
if (-not ([System.IO.Path]::IsPathRooted($outputIsoPath)))
{
    $outputIsoPath = [System.IO.Path]::GetFullPath((Join-Path $pwd $outputIsoPath))
}

# Make sure the temp folder path is an absolute path
if (-not ([System.IO.Path]::IsPathRooted($tempPath)))
{
    $tempPath = [System.IO.Path]::GetFullPath((Join-Path $pwd $tempPath))
}

if (-not (Test-Path -Path $tempPath))
{
    $newLocation = New-Item -Path $tempPath -ItemType Directory -Force
    Write-Output "The temp folder, $($newLocation.FullName) has been created."
}

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

    Write-Output 'Searching for update files ...'
    $updates = Get-LatestUpdate `
        -WindowsVersion Windows10 `
        -Build $buildNumber `
        -Architecture x64 `
        @commonParameterSwitches
    Write-Output "Found $($updates.Length) updates."

    for ($i = 0; $i -lt $updates.Length; $i++)
    {
        Write-Output "Update $($i):"
        Write-Output $updates[$i]
    }

    Write-Output 'Downloading update files ...'
    Save-LatestUpdate `
        -Updates $updates `
        -Path $updatesPath
    Write-Output "Downloaded $($updates.Length) updates."

    # Now load the ISO and then patch it
    # From here: https://gist.github.com/PatrickLang/f8f3486cbbb49e0bb3f9c97e491c3981

    $volumesPriorToMapping = @( $(get-volume | Where-Object FileSystem -eq UDF | Select-Object -ExpandProperty DriveLetter ) )
    Write-Output "DVD volumes in use: $( $volumesPriorToMapping -join ',' )"

    # Mount the installer ISO
    Write-Output 'Mounting ISO file ...'
    Mount-DiskImage $isoFilePath @commonParameterSwitches

    # Figure out which drive the ISO got mounted to
    $volumesAfterMapping = @( $(get-volume | Where-Object FileSystem -eq UDF | Select-Object -ExpandProperty DriveLetter ) )
    Write-Output "DVD volumes in use: $( $volumesAfterMapping -join ',' )"

    $volume = $volumesAfterMapping | Where-Object { $volumesPriorToMapping -notcontains $_ } | Select-Object -First 1
    Write-Output "ISO file mounted at $($volume):"

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
    robocopy "$($volume):" $originalIsoFilePath /s /e

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
catch
{
    $currentErrorActionPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'

    try
    {
        $errorRecord = $Error[0]
        Write-Error $errorRecord.Exception
        Write-Error $errorRecord.ScriptStackTrace
        Write-Error $errorRecord.InvocationInfo.PositionMessage
    }
    finally
    {
        $ErrorActionPreference = $currentErrorActionPreference
    }

    throw
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
