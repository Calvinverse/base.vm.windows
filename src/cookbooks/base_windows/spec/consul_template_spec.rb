# frozen_string_literal: true

require 'spec_helper'

describe 'base_windows::consul_template' do
  service_name = 'consul-template'
  consul_template_config_file = 'base.hcl'

  consul_template_config_config_path = 'c:/config/consul-template/config'
  consul_template_config_templates_path = 'c:/config/consul-template/templates'
  consul_template_logs_path = 'c:/logs/consul-template'
  consul_template_bin_path = 'c:/ops/consul-template'

  context 'create the user to run the service with' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'creates the consul-template user' do
      expect(chef_run).to run_powershell_script('consul_template_user_with_password_that_does_not_expire')
    end
  end

  context 'create the log locations' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'creates the consul-template logs directory' do
      expect(chef_run).to create_directory(consul_template_logs_path)
    end
  end

  context 'create the config locations' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'creates the consul-template configuration file directory' do
      expect(chef_run).to create_directory(consul_template_config_config_path)
    end

    it 'creates the consul-template templates directory' do
      expect(chef_run).to create_directory(consul_template_config_templates_path)
    end
  end

  context 'create the consul-template locations' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'creates the consul-template base directory' do
      expect(chef_run).to create_directory(consul_template_bin_path)
    end

    it 'creates consul-template.exe in the consul-template ops directory' do
      expect(chef_run).to extract_seven_zip_archive(consul_template_bin_path)
    end
  end

  context 'install consul-template as service' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    win_service_name = 'consul-template_service'
    it 'downloads the winsw file' do
      expect(chef_run).to create_remote_file("#{consul_template_bin_path}/#{win_service_name}.exe")
    end

    service_exe_config_content = <<~XML
      <configuration>
          <runtime>
              <generatePublisherEvidence enabled="false"/>
          </runtime>
      </configuration>
    XML
    it 'creates consul-template_service.exe.config in the consul-template ops directory' do
      expect(chef_run).to create_file("#{consul_template_bin_path}/#{win_service_name}.exe.config").with_content(service_exe_config_content)
    end

    consul_template_service_script_content = <<~POWERSHELL
      [CmdletBinding()]
      param(
      )

      function Get-KeyFromConsulKv
      {
        [CmdletBinding()]
        param(
          [string] $key
        )

        $output = & "c:/ops/consul/consul.exe" kv get $key 2>&1
        if ($LASTEXITCODE -eq 0)
        {
          return $output
        }
        else
        {
          return ''
        }
      }

      function Remove-KeyFromConsulKv
      {
        [CmdletBinding()]
        param(
          [string] $key
        )

        $output = & "c:/ops/consul/consul.exe" kv delete $key 2>&1
        if ($LASTEXITCODE -eq 0)
        {
          Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') - Removed the '$key' key from the consul k-v store"
        }
        else
        {
          Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') - No key at '$key' found to remove from the consul k-v store"
        }
      }

      function Invoke-Script
      {
        Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') - Searching for the Vault key for Consul-Template in the Consul k-v ... "
        $hostname = $env:ComputerName
        $vaultKeyPath = "auth/services/templates/$($hostname)/secrets"
        $vaultKey = Get-KeyFromConsulKv -key $vaultKeyPath

        $envVars=""
        $vaultOptions=""

        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
        $startInfo.FileName = "c:/ops/consul-template/consul-template.exe"
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true

        if ($vaultKey -ne '')
        {
          Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') - Found the Vault key for Consul-Template in the Consul k-v. Removing k-v entry ... "
          Remove-KeyFromConsulKv -key $vaultKeyPath

          Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') - Removed k-v entry"

          $startInfo.EnvironmentVariables.Add('VAULT_TOKEN', $vaultKey)

          $serviceName = Get-KeyFromConsulKv -key 'config/services/secrets/protocols/http/host'
          $domain= Get-KeyFromConsulKv -key 'config/services/consul/domain'
          $ort= Get-KeyFromConsulKv -key 'config/services/secrets/protocols/http/port'
          $vaultOptions="-vault-addr=http://$($serviceName).service.$($domain):$($port) -vault-unwrap-token -vault-renew-token -vault-retry"
        }

        $startInfo.Arguments = "-config=""c:/config/consul-template/config"" $($vaultOptions)"

        Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') - Starting Consul-Template ... "
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $startInfo

        # Adding event handers for stdout and stderr.
        $writeToFileEvent = {
          if (-not ([String]::IsNullOrEmpty($EventArgs.Data)))
          {
            Out-File -FilePath $Event.MessageData -Append -InputObject $EventArgs.Data
          }
        }

        $stdOutEvent = Register-ObjectEvent `
          -InputObject $process `
          -Action $writeToFileEvent `
          -EventName 'OutputDataReceived' `
          -MessageData '#{consul_template_logs_path}/consul-template.out.log'
        $stdErrEvent = Register-ObjectEvent `
          -InputObject $process `
          -Action $writeToFileEvent `
          -EventName 'ErrorDataReceived' `
          -MessageData '#{consul_template_logs_path}/consul-template.err.log'

        try
        {
          $process.Start() | Out-Null
          try
          {
            $process.BeginOutputReadLine()
            $process.BeginErrorReadLine()

            while (-not ($process.HasExited))
            {
              Start-Sleep -Seconds 5
            }
          }
          finally
          {
            if (-not ($process.HasExited))
            {
              $process.Close()
            }
          }
        }
        finally
        {
          Unregister-Event -SourceIdentifier $stdOutEvent.Name
          Unregister-Event -SourceIdentifier $stdErrEvent.Name
        }

        Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') - Consul-Template stopped"
      }

      # =============================================================================

      # Fire up
      Invoke-Script
    POWERSHELL
    it 'creates Invoke-ConsulTemplate.ps1 script in the consul-template ops directory' do
      expect(chef_run).to create_file("#{consul_template_bin_path}/Invoke-ConsulTemplate.ps1").with_content(consul_template_service_script_content)
    end

    consul_template_service_xml_content = <<~XML
      <?xml version="1.0"?>
      <service>
          <id>#{service_name}</id>
          <name>#{service_name}</name>
          <description>This service runs the consul-template agent.</description>

          <executable>powershell.exe</executable>
          <argument>-NoLogo</argument>
          <argument>-NonInteractive</argument>
          <argument>-NoProfile</argument>
          <argument>-File</argument>
          <argument>"#{consul_template_bin_path}/Invoke-ConsulTemplate.ps1"</argument>
          <stoptimeout>30sec</stoptimeout>

          <logpath>#{consul_template_logs_path}</logpath>
          <log mode="roll-by-size">
              <sizeThreshold>10240</sizeThreshold>
              <keepFiles>1</keepFiles>
          </log>
          <onfailure action="restart"/>
      </service>
    XML
    it 'creates consul_service.xml in the consul ops directory' do
      expect(chef_run).to create_file("#{consul_template_bin_path}/#{win_service_name}.xml").with_content(consul_template_service_xml_content)
    end

    it 'installs consul-template as service' do
      expect(chef_run).to run_powershell_script('consul_template_as_service')
    end

    it 'creates the windows service event log' do
      expect(chef_run).to create_registry_key("HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\services\\eventlog\\Application\\#{service_name}").with(
        values: [{
          name: 'EventMessageFile',
          type: :string,
          data: 'c:\\Windows\\Microsoft.NET\\Framework64\\v4.0.30319\\EventLogMessages.dll'
        }]
      )
    end

    consul_template_default_config_content = <<~HCL
      # This denotes the start of the configuration section for Consul. All values
      # contained in this section pertain to Consul.
      consul {
        # This block specifies the basic authentication information to pass with the
        # request. For more information on authentication, please see the Consul
        # documentation.
        auth {
          enabled  = false
          username = "test"
          password = "test"
        }

        # This is the address of the Consul agent. By default, this is
        # 127.0.0.1:8500, which is the default bind and port for a local Consul
        # agent. It is not recommended that you communicate directly with a Consul
        # server, and instead communicate with the local Consul agent. There are many
        # reasons for this, most importantly the Consul agent is able to multiplex
        # connections to the Consul server and reduce the number of open HTTP
        # connections. Additionally, it provides a "well-known" IP address for which
        # clients can connect.
        address = "127.0.0.1:8500"

        # This is the ACL token to use when connecting to Consul. If you did not
        # enable ACLs on your Consul cluster, you do not need to set this option.
        #
        # This option is also available via the environment variable CONSUL_TOKEN.
        #token = "abcd1234"

        # This controls the retry behavior when an error is returned from Consul.
        # Consul Template is highly fault tolerant, meaning it does not exit in the
        # face of failure. Instead, it uses exponential back-off and retry functions
        # to wait for the cluster to become available, as is customary in distributed
        # systems.
        retry {
          # This enabled retries. Retries are enabled by default, so this is
          # redundant.
          enabled = true

          # This specifies the number of attempts to make before giving up. Each
          # attempt adds the exponential backoff sleep time. Setting this to
          # zero will implement an unlimited number of retries.
          attempts = 12

          # This is the base amount of time to sleep between retry attempts. Each
          # retry sleeps for an exponent of 2 longer than this base. For 5 retries,
          # the sleep times would be: 250ms, 500ms, 1s, 2s, then 4s.
          backoff = "250ms"

          # This is the maximum amount of time to sleep between retry attempts.
          # When max_backoff is set to zero, there is no upper limit to the
          # exponential sleep between retry attempts.
          # If max_backoff is set to 10s and backoff is set to 1s, sleep times
          # would be: 1s, 2s, 4s, 8s, 10s, 10s, ...
          max_backoff = "1m"
        }

        # This block configures the SSL options for connecting to the Consul server.
        ssl {
          # This enables SSL. Specifying any option for SSL will also enable it.
          enabled = false

          # This enables SSL peer verification. The default value is "true", which
          # will check the global CA chain to make sure the given certificates are
          # valid. If you are using a self-signed certificate that you have not added
          # to the CA chain, you may want to disable SSL verification. However, please
          # understand this is a potential security vulnerability.
          # verify = false

          # This is the path to the certificate to use to authenticate. If just a
          # certificate is provided, it is assumed to contain both the certificate and
          # the key to convert to an X509 certificate. If both the certificate and
          # key are specified, Consul Template will automatically combine them into an
          # X509 certificate for you.
          # cert = "/path/to/client/cert"
          # key  = "/path/to/client/key"

          # This is the path to the certificate authority to use as a CA. This is
          # useful for self-signed certificates or for organizations using their own
          # internal certificate authority.
          # ca_cert = "/path/to/ca"

          # This is the path to a directory of PEM-encoded CA cert files. If both
          # `ca_cert` and `ca_path` is specified, `ca_cert` is preferred.
          # ca_path = "path/to/certs/"

          # This sets the SNI server name to use for validation.
          # server_name = "my-server.com"
        }
      }

      # This is the signal to listen for to trigger a reload event. The default
      # value is shown below. Setting this value to the empty string will cause CT
      # to not listen for any reload signals.
      reload_signal = "SIGHUP"

      # This is the signal to listen for to trigger a graceful stop. The default
      # value is shown below. Setting this value to the empty string will cause CT
      # to not listen for any graceful stop signals.
      kill_signal = "SIGINT"

      # This is the maximum interval to allow "stale" data. By default, only the
      # Consul leader will respond to queries; any requests to a follower will
      # forward to the leader. In large clusters with many requests, this is not as
      # scalable, so this option allows any follower to respond to a query, so long
      # as the last-replicated data is within these bounds. Higher values result in
      # less cluster load, but are more likely to have outdated data.
      max_stale = "10m"

      # This is the log level. If you find a bug in Consul Template, please enable
      # debug logs so we can help identify the issue. This is also available as a
      # command line flag.
      log_level = "info"

      # This is the path to store a PID file which will contain the process ID of the
      # Consul Template process. This is useful if you plan to send custom signals
      # to the process.
      pid_file = "#{consul_template_logs_path}/pid.txt"

      # This is the quiescence timers; it defines the minimum and maximum amount of
      # time to wait for the cluster to reach a consistent state before rendering a
      # template. This is useful to enable in systems that have a lot of flapping,
      # because it will reduce the the number of times a template is rendered.
      wait {
        min = "5s"
        max = "10s"
      }

      # This block defines the configuration for connecting to a syslog server for
      # logging.
      syslog {
        # This enables syslog logging. Specifying any other option also enables
        # syslog logging.
        #enabled = true

        # This is the name of the syslog facility to log to.
        #facility = "syslog"
      }

      # This block defines the configuration for de-duplication mode. Please see the
      # de-duplication mode documentation later in the README for more information
      # on how de-duplication mode operates.
      deduplicate {
        # This enables de-duplication mode. Specifying any other options also enables
        # de-duplication mode.
        enabled = false

        # This is the prefix to the path in Consul's KV store where de-duplication
        # templates will be pre-rendered and stored.
        # prefix = "consul-template/dedup/"
      }
    HCL
    it 'creates default.hcl in the consul-template config directory' do
      expect(chef_run).to create_file("#{consul_template_config_config_path}/#{consul_template_config_file}").with_content(consul_template_default_config_content)
    end
  end
end
