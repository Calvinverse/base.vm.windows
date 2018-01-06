Describe 'The consul-template application' {
    Context 'is installed' {
        It 'with binaries in c:\ops\consul-template' {
            'c:\ops\consul-template\consul-template.exe' | Should Exist
            'c:\ops\consul-template\consul-template_service.exe' | Should Exist
            'c:\ops\consul-template\consul-template_service.exe.config' | Should Exist
            'c:\ops\consul-template\consul-template_service.xml' | Should Exist
        }

        It 'with default configuration in c:\ops\consul-template\config' {
            'c:\config\consul-template\config\base.hcl' | Should Exist
            'c:\config\consul-template\config\vault.hcl' | Should Exist
        }
    }

    Context 'has been made into a service' {
        $service = Get-Service consul-template

        It 'that is enabled' {
            $service.StartType | Should Match 'Automatic'
        }

        It 'and is running' {
            $service.Status | Should Match 'Running'
        }
    }
}
