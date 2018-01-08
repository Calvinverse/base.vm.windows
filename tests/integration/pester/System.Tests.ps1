$global:progresspreference = 'SilentlyContinue'

Describe 'On the system' {
    Context 'the machine name' {
        It 'should not be the test name' {
            $env:COMPUTERNAME | Should Not Be '${ImageName}'
        }
    }

    Context 'the time zone' {
        It 'should be on UTC time' {
            ([System.TimeZone]::CurrentTimeZone).StandardName | Should Be 'Coordinated Universal Time'
        }
    }

    Context 'the administrator rights' {
        $wmiGroups = Get-WmiObject win32_groupuser
        $admins = $wmiGroups | Where-Object { $_.groupcomponent -like '*"Administrators"' }

        $userNames = @()
        $admins | foreach-object {
            $_.partcomponent -match ".+Domain\=(.+)\,Name\=(.+)$" | Out-Null
            $userNames += $matches[1].trim('"') + "\" + $matches[2].trim('"')
        }

        It 'should only have the default Administrator' {
            $userNames.Length | Should Be 1
            $userNames[0] | Should Be "$($env:COMPUTERNAME)\Administrator"
        }
    }

    Context 'system updates' {
        $criteria = "Type='software' and IsAssigned=1 and IsHidden=0 and IsInstalled=0"

        $searcher = (New-Object -COM Microsoft.Update.Session).CreateUpdateSearcher()
        $updates  = $searcher.Search($criteria).Updates

        $updatesThatAreNotWindowsDefender = @($updates | Where-Object { -not $_.Title.StartsWith('Definition Update for Windows Defender') })
        It 'should all be installed' {
            $updatesThatAreNotWindowsDefender.Length | Should Be 0
        }
    }

    Context 'the SMB1 windows feature' {
        It 'has been removed' {
            $feature = Get-WindowsFeature -Name 'FS-SMB1' -ErrorAction SilentlyContinue
            $feature.InstallState | Should Be 'Available'
        }
    }

    Context 'system metrics' {
        It 'with binaries in c:\ops\scollector' {
            'c:\ops\scollector\scollector.exe' | Should Exist
        }

        It 'with default configuration in c:\config\scollector\scollector.toml' {
            'c:\config\scollector\scollector.toml' | Should Exist
        }

        $expectedContent = @'
Host = "http://opentsdb.metrics.service.integrationtest:4242"

[Tags]
    environment = "test-integration"
    os = "windows"

'@
        $scollectorConfigContent = Get-Content 'c:\config\scollector\scollector.toml' | Out-String
        It 'with the expected content in the configuration file' {
            $scollectorConfigContent | Should Be $expectedContent
        }
    }

    Context 'has been turned into a service' {
        $service = Get-Service scollector

        It 'that is enabled' {
            $service.StartType | Should Match 'Automatic'
        }

        It 'and is running' {
            #$service.Status | Should Match 'Running'
        }
    }
}
