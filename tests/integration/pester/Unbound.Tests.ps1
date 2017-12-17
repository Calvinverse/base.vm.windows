Describe 'The unbound application' {
    Context 'is installed' {
        It 'with binaries in c:\ops\unbound' {
            'c:\ops\unbound\unbound.exe' | Should Exist
        }

        It 'with default configuration in c:\ops\unbound' {
            'c:\ops\unbound\unbound.conf' | Should Exist
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
            $result = Resolve-DnsName -Name 'google.com' -DnsOnly -NoHostsFile
            $result.Length | Should BeGreaterThan 0
        }
    }
}
