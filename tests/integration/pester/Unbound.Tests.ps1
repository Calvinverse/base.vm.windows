Describe 'The unbound application' {
    Context 'is installed' {
        It 'with binaries in c:\Program Files\unbound' {
            'c:\Program Files\unbound\unbound.exe' | Should Exist
        }

        It 'with default configuration in c:\ops\unbound' {
            'c:\Program Files\unbound\service.conf' | Should Exist
        }

        It 'with environment configuration in c:\config\unbound' {
            'c:\config\unbound\unbound_zones.conf' | Should Exist
        }
    }

    Context 'has been made into a service' {
        $service = Get-Service unbound

        It 'that is enabled' {
            $service.StartType | Should Match 'Automatic'
        }

        It 'and is running' {
            $service.Status | Should Match 'Running'
        }
    }

    Context 'DNS resoluton works' {
        It 'for external addresses' {
            $result = Resolve-DnsName -Name 'google.com' -DnsOnly -NoHostsFile -Type A
            $result.Length | Should BeGreaterThan 0
        }

        $localIpAddress = (Get-NetIPConfiguration).IPv4Address
        It 'for consul addresses' {
            $result = Resolve-DnsName -Name 'consul.service.integrationtest' -DnsOnly -NoHostsFile -Type A
            $result | Should Not Be $null
            $result.IP4Address | Should Be $localIpAddress.IPAddress
        }

        It 'for host names' {
            $result = Resolve-DnsName -Name $env:COMPUTERNAME -DnsOnly -NoHostsFile -Type A
            $result | Should Not Be $null
            $result.IP4Address | Should Be $localIpAddress.IPAddress
        }
    }
}
