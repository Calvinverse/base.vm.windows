Describe 'The telegraf application' {
    Context 'is installed' {
        It 'with binaries in c:\ops\telegraf' {
            'c:\ops\telegraf\telegraf.exe' | Should Exist
        }

        It 'with default configuration in c:\ops\telegraf' {
            'c:\ops\telegraf\telegraf.conf' | Should Exist
        }
    }

    Context 'has been made into a service' {
        $service = Get-Service telegraf

        It 'that is enabled' {
            $service.StartType | Should Match 'Automatic'
        }

        It 'and is running' {
            $service.Status | Should Match 'Running'
        }
    }
}
