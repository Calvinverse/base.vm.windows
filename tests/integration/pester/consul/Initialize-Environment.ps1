function Get-IpAddress
{
    $interface = Get-NetIPConfiguration |
        Where-Object { $_.NetAdapter.Status -eq 'Up' -and $_.NetProfile.IPv4Connectivity -ne 'NoTraffic' } |
        Select-Object -First 1
    return $interface.IPv4Address.IPAddress
}

function Initialize-Environment
{
    $consulVersion = '1.0.2'
    Start-TestConsul -consulVersion $consulVersion
    Join-Cluster -consulVersion $consulVersion
    Set-ConsulKV -consulVersion $consulVersion

    Write-Output "Giving consul-template 30 seconds to process the data ..."
    Start-Sleep -Seconds 30
}

function Join-Cluster
{
    [CmdletBinding()]
    param(
        [string] $consulVersion
    )

    Write-Output "Joining the local consul ..."

    # connect to the actual local consul instance
    $ipAddress = Get-IpAddress
    Write-Output "Joining: $($ipAddress):8351"

    Start-Process -FilePath 'c:\ops\consul\consul.exe' -ArgumentList "join $($ipAddress):8351"

    Write-Output "Getting members for client"
    & 'c:\ops\consul\consul.exe' members

    Write-Output "Getting members for server"
    & 'c:\ops\consul\consul.exe' members -http-addr=http://127.0.0.1:8550

}

function Set-ConsulKV
{
    [CmdletBinding()]
    param(
        [string] $consulVersion
    )

    Write-Output "Setting consul key-values ..."

    # Load config/services/consul
    & 'c:\ops\consul\consul.exe' kv put -http-addr=http://127.0.0.1:8550 config/services/consul/datacenter 'test-integration'
    & 'c:\ops\consul\consul.exe' kv put -http-addr=http://127.0.0.1:8550 config/services/consul/domain 'integrationtest'

    # load config/services/metrics
    & 'c:\ops\consul\consul.exe' kv put -http-addr=http://127.0.0.1:8550 config/services/metrics/protocols/opentsdb/host 'opentsdb.metrics'
    & 'c:\ops\consul\consul.exe' kv put -http-addr=http://127.0.0.1:8550 config/services/metrics/protocols/opentsdb/port '4242'

    # load config/services/queue
    #& 'c:\ops\consul\consul.exe' kv put -http-addr=http://127.0.0.1:8550 config/services/queue/host 'active.queue'
    #& 'c:\ops\consul\consul.exe' kv put -http-addr=http://127.0.0.1:8550 config/services/queue/port '5672'

    #& 'c:\ops\consul\consul.exe' kv put -http-addr=http://127.0.0.1:8550 config/services/queue/logs/syslog/username 'testuser'
    #& 'c:\ops\consul\consul.exe' kv put -http-addr=http://127.0.0.1:8550 config/services/queue/logs/syslog/vhost 'testlogs'
}

function Start-TestConsul
{
    [CmdletBinding()]
    param(
        [string] $consulVersion
    )

    Write-Output "Starting consul ..."
    $process = Start-Process -FilePath 'c:\ops\consul\consul.exe' -ArgumentList "agent -config-file c:\temp\pester\consul\server.json" -PassThru -RedirectStandardOutput c:\temp\pester\consul\consuloutput.out -RedirectStandardError c:\temp\pester\consul\consulerror.out

    Write-Output "Going to sleep for 10 seconds ..."
    Start-Sleep -Seconds 10
}
