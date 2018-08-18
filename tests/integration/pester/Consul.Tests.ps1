Describe 'The consul application' {
    Context 'is installed' {
        It 'with binaries in c:\ops\consul' {
            'c:\ops\consul\consul.exe' | Should Exist
            'c:\ops\consul\consul_service.exe' | Should Exist
        }

        It 'with default configuration in c:\ops\consul' {
            'c:\ops\consul\consul_base.json' | Should Exist
            'c:\ops\consul\consul_service.exe.config' | Should Exist
            'c:\ops\consul\consul_service.xml' | Should Exist
        }

        It 'with environment configuration in c:\config\consul' {
            'c:\config\consul\location.json' | Should Exist
            'c:\config\consul\metrics.json' | Should Exist
            'c:\config\consul\region.json' | Should Exist
            'c:\config\consul\secrets.json' | Should Exist
        }
    }

    Context 'has been made into a service' {
        $service = Get-Service consul

        It 'that is enabled' {
            $service.StartType | Should Match 'Automatic'
        }

        It 'and is running' {
            $service.Status | Should Match 'Running'
        }
    }

    Context 'can be contacted' {
        $response = Invoke-WebRequest -Uri http://localhost:8500/v1/agent/self -UseBasicParsing
        $agentInformation = ConvertFrom-Json $response.Content
        It 'responds to HTTP calls' {
            $response.StatusCode | Should Be 200
            $agentInformation | Should Not Be $null
        }

        It 'is not a server instance' {
            $agentInformation.Config.Server | Should Be $false
        }
    }
}
