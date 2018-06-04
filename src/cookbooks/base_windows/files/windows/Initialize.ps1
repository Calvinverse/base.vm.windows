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

    Set-Service `
        -Name $serviceName `
        -StartupType Automatic `
        @commonParameterSwitches

    $service = Get-Service -Name $serviceName @commonParameterSwitches
    if ($service.Status -ne 'Running')
    {
        Start-Service -Name $serviceName @commonParameterSwitches
    }
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
        $cd = Get-WMIObject -Class Win32_CDROMDrive -ErrorAction Stop
    }
    catch
    {
        Continue;
    }

    return $cd.Drive
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

    EnableAndStartService -serviceName 'consul' @commonParameterSwitches
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

    Set-DnsIpAddresses @commonParameterSwitches
    EnableAndStartService -serviceName 'unbound' @commonParameterSwitches
}

function Set-DnsIpAddresses
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

    # Get all the physical network adapters that provide IPv4 services, are enabled and are the preferred network interface (because that's what unbound will be
    # transmitting on).
    $adapter = Get-NetAdapter -Physical | Where-Object { Get-NetIPAddress -InterfaceIndex $_.ifIndex -AddressFamily IPv4 -AddressState Preferred -ErrorAction SilentlyContinue }

    # Add the unbound IP address to the list of DNS servers and make sure it's the first one so that it gets the first go at
    # resolving all the DNS queries.
    $localhost = '127.0.0.1'
    $serverDnsAddresses = @( $localhost )
    Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $serverDnsAddresses -Verbose
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
    # - The major and minor version to be a single character
    # - The patch version up to 2 characters
    # - The post-fix to be 3 characters
    $resourceShortName = $env:RESOURCE_SHORT_NAME.ToString().Substring(4)
    $postfix = -join ((65..90) + (97..122) | Get-Random -Count 3 | % {[char]$_})
    $name = "cv$($resourceShortName)-$($env:RESOURCE_VERSION_MAJOR)$($env:RESOURCE_VERSION_MINOR)$($env:RESOURCE_VERSION_PATCH)-$($postfix)"

    Rename-Computer -NewName $name @commonParameterSwitches
}
