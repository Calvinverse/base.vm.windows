$global:progresspreference = 'SilentlyContinue'

Describe 'The firewall' {
    Context 'on the machine' {
        $firewallProfiles = Get-NetFirewallProfile
        foreach($profile in $firewallProfiles)
        {
            It "should be enabled for the '$($profile.Name)' profile" {
                $profile.Enabled | Should Be $true
            }
        }
    }

    <#

    # This test is removed for now because we don't know how to turn ping on. It might have to do
    # with the network location which needs to be set to private but isn't by default. Additionally
    # it's not possible to set that in the base image because the network interface will change
    # when the base image is used.

    Context 'Should allow Ping' {
        $rules = @( Get-NetFirewallRule -Enabled True | Where-Object { $_.DisplayName.StartsWith('ICMP') } )
        $rules.Length | Should Be 1
        $port = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rules[0]

        $port.Protocol | Should Be 'ICMPv4'
        $port.LocalPort | Should Be 'RPC'
        $port.RemotePort | Should Be 'Any'
    }
    #>

    Context 'Should allow WinRM' {
        $rules = @( Get-NetFirewallRule -DisplayGroup 'Windows Remote Management' -Enabled True )
        $rules.Length | Should Be 2 # Ideally only 1 because we only want the Domain / Private profile to allow WinRM, but the public profile has one too
        $port = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rules[0]

        $port.Protocol | Should Be 'TCP'
        $port.LocalPort | Should Be 5985
        $port.RemotePort | Should Be 'Any'
    }

    Context 'Should not allow remote desktop' {
        $rules = @( Get-NetFirewallRule -DisplayGroup 'Remote Desktop' -Enabled True -ErrorAction SilentlyContinue )
        $rules.Length | Should Be 0
    }

    Context 'Should not allow network discovery' {
        $rules = @( Get-NetFirewallRule -DisplayGroup 'Network Discovery' -Enabled True -ErrorAction SilentlyContinue )
        $rules.Length | Should Be 0
    }

    Context 'Should allow consul' {
        #$rules = @( Get-NetFirewallRule -DisplayGroup 'Windows Remote Management' -Enabled True )
        #$rules.Length | Should Be 2 # Ideally only 1 because we only want the Domain / Private profile to allow WinRM, but the public profile has one too
        #$port = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rules[0]

        #$port.Protocol | Should Be 'TCP'
        #$port.LocalPort | Should Be 5985
        #$port.RemotePort | Should Be 'Any'

        # Ports
        # 8300
        # 8301
        # 8302
        # 8500
        # 8600
    }

    # Allow telegraf on port 8125

    # Allow unbound on port 53
}
