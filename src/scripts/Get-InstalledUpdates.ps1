[CmdletBinding()]
param(
    [string] $outputFile = 'c:\temp\installed_updates.txt'
)

$ErrorActionPreference = 'Stop'

$commonParameterSwitches =
    @{
        Verbose = $PSBoundParameters.ContainsKey('Verbose');
        Debug = $false;
        ErrorAction = "Stop"
    }

$directory = Split-Path -Path $outputFile -Parent
if (-not (Test-Path $directory))
{
    New-Item -Path $directory -ItemType Directory | Out-Null
}

$UpdateSession = New-Object -ComObject Microsoft.Update.Session
$SearchResult = $null
$UpdateSearcher = $UpdateSession.CreateUpdateSearcher()
$UpdateSearcher.Online = $true
$SearchResult = $UpdateSearcher.Search("IsInstalled=1 and Type='Software'")

foreach($Update in $SearchResult.Updates)
{
    $line = "$($Update.Title + " | " + $update.CveIDs + " | " + $update.KBArticleIDs)"
    Out-File -FilePath $outputFile -Append -NoClobber -InputObject $line
}
