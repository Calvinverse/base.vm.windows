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

        It 'should all be installed' {
            $updates.Count | Should Be 0
        }
    }

    Context 'the SMB1 windows feature' {
        It 'has been removed' {
            $feature = Get-WindowsFeature -Name 'FS-SMB1' -ErrorAction SilentlyContinue
            $feature.InstallState | Should Be 'Available'
        }
    }
}
