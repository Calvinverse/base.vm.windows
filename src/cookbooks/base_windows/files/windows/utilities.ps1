function Disable-ProvisioningService
{
    [CmdletBinding()]
    param(
    )

    $ErrorActionPreference = 'Stop'

    $commonParameterSwitches =
        @{
            Verbose = $PSBoundParameters.ContainsKey('Verbose');
            Debug = $false;
            ErrorAction = "Stop"
        }

    try
    {
        Set-Service `
            -Name 'Provisioning' `
            -StartupType Disabled `
            @commonParameterSwitches
    }
    catch
    {
        Write-Error "Failed to stop the service. Error was $($_.Exception.ToString())"
    }
}

function EnableAndStartService
{
    [CmdletBinding()]
    param(
        [string] $serviceName
    )

    $ErrorActionPreference = 'Stop'

    $commonParameterSwitches =
        @{
            Verbose = $PSBoundParameters.ContainsKey('Verbose');
            Debug = $false;
            ErrorAction = "Stop"
        }

    EnableService -serviceName $serviceName

    $service = Get-Service -Name $serviceName @commonParameterSwitches
    if ($service.Status -ne 'Running')
    {
        Start-Service -Name $serviceName @commonParameterSwitches
    }
}

function EnableService
{
    [CmdletBinding()]
    param(
        [string] $serviceName
    )

    $ErrorActionPreference = 'Stop'

    $commonParameterSwitches =
        @{
            Verbose = $PSBoundParameters.ContainsKey('Verbose');
            Debug = $false;
            ErrorAction = "Stop"
        }

    Set-Service `
        -Name $serviceName `
        -StartupType Automatic `
        @commonParameterSwitches
}

function Find-DvdDriveLetter
{
    [CmdletBinding()]
    param(
    )

    $ErrorActionPreference = 'Stop'

    $commonParameterSwitches =
        @{
            Verbose = $PSBoundParameters.ContainsKey('Verbose');
            Debug = $false;
            ErrorAction = "Stop"
        }

    try
    {
        $cd = @( Get-WMIObject -Class Win32_CDROMDrive @commonParameterSwitches )
    }
    catch
    {
        Write-Verbose "Failed to find DVD. Error is $($_.Exception.ToString())"
        return $null
    }

    if ($null -ne $cd)
    {
        if ($cd.Length -eq 0)
        {
            Write-Verbose "Failed to find DVD. Found zero devices."
            return $null
        }

        if ($cd.Length -eq 1)
        {
            return $cd[0].Drive
        }
        else
        {
            Write-Verbose "More than one DVD device found. Found $($cd.Length) devices"
            return $null
        }
    }

    Write-Verbose "Failed to find DVD. Found zero devices."
    return $null
}

function Initialize-Consul
{
    [CmdletBinding()]
    param(
        [string] $dvdDriveLetter
    )

    $ErrorActionPreference = 'Stop'

    $commonParameterSwitches =
        @{
            Verbose = $PSBoundParameters.ContainsKey('Verbose');
            Debug = $false;
            ErrorAction = "Stop"
        }

    Copy-Item -Path (Join-Path $dvdDriveLetter 'consul\consul_region.json') -Destination 'c:\config\consul\region.json' -Force @commonParameterSwitches
    Copy-Item -Path (Join-Path $dvdDriveLetter 'consul\consul_secrets.json') -Destination 'c:\config\consul\secrets.json' -Force @commonParameterSwitches

    $dvdFilePath = Join-Path $dvdDriveLetter 'consul\client\consul_client_location.json'
    if (Test-Path $dvdFilePath)
    {
        Copy-Item -Path $dvdFilePath -Destination 'c:\config\consul\location.json' -Force @commonParameterSwitches
    }

    EnableService -serviceName 'consul' @commonParameterSwitches
}

function Initialize-ConsulTemplate
{
    [CmdletBinding()]
    param(
        [string] $dvdDriveLetter
    )

    $ErrorActionPreference = 'Stop'

    $commonParameterSwitches =
        @{
            Verbose = $PSBoundParameters.ContainsKey('Verbose');
            Debug = $false;
            ErrorAction = "Stop"
        }

    EnableService -serviceName 'consul-template' @commonParameterSwitches
}

function Initialize-Unbound
{
    [CmdletBinding()]
    param(
        [string] $dvdDriveLetter
    )

    $ErrorActionPreference = 'Stop'

    $commonParameterSwitches =
        @{
            Verbose = $PSBoundParameters.ContainsKey('Verbose');
            Debug = $false;
            ErrorAction = "Stop"
        }

    Copy-Item -Path (Join-Path $dvdDriveLetter 'unbound\unbound_zones.conf') -Destination 'c:\config\unbound\unbound_zones.conf' -Force @commonParameterSwitches

    $consulRegion = ConvertFrom-Json (Get-Content -Path (Join-Path $dvdDriveLetter 'consul\consul_region.json') | Out-String)

    Set-DnsIpAddresses -domain $consulRegion.domain @commonParameterSwitches
    EnableAndStartService -serviceName 'unbound' @commonParameterSwitches
}

function Set-DnsIpAddresses
{
    [CmdletBinding()]
    param(
        [string] $domain
    )

    $ErrorActionPreference = 'Stop'

    $commonParameterSwitches =
        @{
            Verbose = $PSBoundParameters.ContainsKey('Verbose');
            Debug = $false;
            ErrorAction = "Stop"
        }

    # Get all the physical network adapters that provide IPv4 services, are enabled and are the preferred network interface (because that's what unbound will be
    # transmitting on).
    $adapter = Get-NetAdapter -Physical | Where-Object { Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -AddressState Preferred -ErrorAction SilentlyContinue }

    # Add the unbound IP address to the list of DNS servers and make sure it's the first one so that it gets the first go at
    # resolving all the DNS queries.
    $localhost = '127.0.0.1'
    $serverDnsAddresses = @( $localhost )
    Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $serverDnsAddresses @commonParameterSwitches
    Set-DnsClient -InterfaceIndex $adapter.InterfaceIndex -ConnectionSpecificSuffix "node.$($domain)" @commonParameterSwitches
}

function Set-HostName
{
    [CmdletBinding()]
    param(
    )

    $ErrorActionPreference = 'Stop'

    $commonParameterSwitches =
        @{
            Verbose = $PSBoundParameters.ContainsKey('Verbose');
            Debug = $false;
            ErrorAction = "Stop"
        }

    # Because windows host names can only be 15 characters we have a problem, so we're expecting:
    # - RESOURCE_SHORT_NAME to be 4 characters
    # - The version number to be no more than 4 numbers. In general we're expecting something like
    #   - The major to be a single character
    #   - Theminor version to either be 1 or 2 characters
    #   - The patch version to be either 1 or 2 characters
    # - The post-fix to be 3 characters
    $resourceShortName = $env:RESOURCE_ACRONYM_NAME
    if (($null -ne $resourceShortName) -and ($resourceShortName -ne ''))
    {
        $length = 4
        if ($resourceShortName.Length -lt $length)
        {
            $length = $resourceShortName.Length
        }
        $resourceShortName = $resourceShortName.ToString().Substring(0, $length).ToLowerInvariant()
    }
    else
    {
        $resourceShortName = ''
    }

    $postfix = -join ((65..90) + (97..122) | Get-Random -Count 3 | Foreach-Object { [char]$_ })
    $name = "di$($resourceShortName)-$($env:RESOURCE_VERSION_MAJOR)$($env:RESOURCE_VERSION_MINOR)$($env:RESOURCE_VERSION_PATCH)-$($postfix.ToLowerInvariant())"

    Rename-Computer -NewName $name @commonParameterSwitches
}

function Set-NetworkLocation
{
    [CmdletBinding()]
    param(
    )

    $ErrorActionPreference = 'Stop'

    $commonParameterSwitches =
        @{
            Verbose = $PSBoundParameters.ContainsKey('Verbose');
            Debug = $false;
            ErrorAction = "Stop"
        }

    # Get all the physical network adapters that provide IPv4 services, are enabled
    $adapters = @(Get-NetAdapter -Physical | Where-Object { Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue })
    foreach($adapter in $adapters)
    {
        Set-NetConnectionProfile -InterfaceIndex $adapter.ifIndex -NetworkCategory Private
    }
}
