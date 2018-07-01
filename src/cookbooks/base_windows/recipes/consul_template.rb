# frozen_string_literal: true

#
# Cookbook Name:: base_windows
# Recipe:: consul_template
#
# Copyright 2017, P. van der Velde
#

# Configure the service user under which consul will be run
service_username = node['consul_template']['service']['user_name']
service_password = node['consul_template']['service']['user_password']

# Configure the service user under which consul-template will be run
# Make sure that the user password doesn't expire. The password is a random GUID, so it is unlikely that
# it will ever be guessed. And the user is a normal user who can't do anything so we don't really care about it
powershell_script 'consul_template_user_with_password_that_does_not_expire' do
  code <<~POWERSHELL
    $userName = '#{service_username}'
    $password = ConvertTo-SecureString -String '#{service_password}' -AsPlainText -Force
    $localUser = New-LocalUser `
      -Name $userName `
      -Password $password `
      -PasswordNeverExpires `
      -UserMayNotChangePassword `
      -AccountNeverExpires `
      -Verbose

    Add-LocalGroupMember `
      -Group 'Administrators' `
      -Member $localUser.Name `
      -Verbose
  POWERSHELL
end

# Grant the user the LogOnAsService permission. Following this anwer on SO: http://stackoverflow.com/a/21235462/539846
# With some additional bug fixes to get the correct line from the export file and to put the correct text in the import file
powershell_script 'consul_template_user_grant_service_logon_rights' do
  code <<~POWERSHELL
    $ErrorActionPreference = 'Stop'

    $userName = '#{service_username}'

    $tempPath = "c:\\temp"
    if (-not (Test-Path $tempPath))
    {
        New-Item -Path $tempPath -ItemType Directory | Out-Null
    }

    $import = Join-Path -Path $tempPath -ChildPath "import.inf"
    if(Test-Path $import)
    {
        Remove-Item -Path $import -Force
    }

    $export = Join-Path -Path $tempPath -ChildPath "export.inf"
    if(Test-Path $export)
    {
        Remove-Item -Path $export -Force
    }

    $secedt = Join-Path -Path $tempPath -ChildPath "secedt.sdb"
    if(Test-Path $secedt)
    {
        Remove-Item -Path $secedt -Force
    }

    $sid = ((New-Object System.Security.Principal.NTAccount($userName)).Translate([System.Security.Principal.SecurityIdentifier])).Value

    secedit /export /cfg $export
    $line = (Select-String $export -Pattern "SeServiceLogonRight").Line
    $sids = $line.Substring($line.IndexOf('=') + 1).Trim()

    if (-not ($sids.Contains($sid)))
    {
        Write-Host ("Granting SeServiceLogonRight to user account: {0} on host: {1}." -f $userName, $computerName)
        $lines = @(
                "[Unicode]",
                "Unicode=yes",
                "[System Access]",
                "[Event Audit]",
                "[Registry Values]",
                "[Version]",
                "signature=`"`$CHICAGO$`"",
                "Revision=1",
                "[Profile Description]",
                "Description=GrantLogOnAsAService security template",
                "[Privilege Rights]",
                "SeServiceLogonRight = $sids,*$sid"
            )
        foreach ($line in $lines)
        {
            Add-Content $import $line
        }

        secedit /import /db $secedt /cfg $import
        secedit /configure /db $secedt
        gpupdate /force
    }
    else
    {
        Write-Host ("User account: {0} on host: {1} already has SeServiceLogonRight." -f $userName, $computerName)
    }
  POWERSHELL
end

#
# INSTALL CONSUL-TEMPLATE
#
service_name = node['consul_template']['service']['name']

consul_template_config_path = node['consul_template']['config_path']
consul_template_template_path = node['consul_template']['template_path']

consul_template_bin_path = "#{node['paths']['ops']}/#{service_name}"
consul_template_logs_path = "#{node['paths']['logs']}/#{service_name}"

%W[#{consul_template_bin_path} #{consul_template_config_path} #{consul_template_template_path}].each do |path|
  directory path do
    action :create
    recursive true
    rights :read_execute, 'Everyone', applies_to_children: true, applies_to_self: false
  end
end

consul_template_zip_path = "#{node['paths']['temp']}/consul-template.zip"
remote_file consul_template_zip_path do
  action :create
  source node['consul-template']['url']
end

consul_template_exe_filename = 'consul-template.exe'
consul_template_exe_path = "#{consul_template_bin_path}/#{consul_template_exe_filename}"
seven_zip_archive consul_template_bin_path do
  overwrite true
  source consul_template_zip_path
  timeout 30
end

# We need to multiple-escape the escape character because of ruby string and regex etc. etc. See here: http://stackoverflow.com/a/6209532/539846
file "#{consul_template_config_path}/base.hcl" do
  action :create
  content <<~HCL
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
end

#
# WINDOWS SERVICE
#

directory consul_template_logs_path do
  action :create
  rights :modify, service_username, applies_to_children: true, applies_to_self: false
end

service_exe_name = node['consul_template']['service']['exe']
remote_file "#{consul_template_bin_path}/#{service_exe_name}.exe" do
  action :create
  source node['winsw']['url']
end

file "#{consul_template_bin_path}/#{service_exe_name}.exe.config" do
  action :create
  content <<~XML
    <configuration>
        <runtime>
            <generatePublisherEvidence enabled="false"/>
        </runtime>
    </configuration>
  XML
end

consul_exe_path = node['consul']['path']['exe']
run_consul_template_script = "#{consul_template_bin_path}/Invoke-ConsulTemplate.ps1"
file run_consul_template_script do
  action :create
  content <<~POWERSHELL
    [CmdletBinding()]
    param(
    )

    function Get-KeyFromConsulKv
    {
      [CmdletBinding()]
      param(
        [string] $key
      )

      $output = & "#{consul_exe_path}" kv get $key 2>&1
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

      $output = & "#{consul_exe_path}" kv delete $key 2>&1
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
      $hostname = ($env:ComputerName).ToLowerInvariant()
      $vaultKeyPath = "auth/services/templates/$($hostname)/secrets"
      $vaultKey = Get-KeyFromConsulKv -key $vaultKeyPath

      $envVars = ""
      $vaultOptions = ""

      $startInfo = New-Object System.Diagnostics.ProcessStartInfo
      $startInfo.FileName = "#{consul_template_exe_path}"
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
        $domain = Get-KeyFromConsulKv -key 'config/services/consul/domain'
        $port = Get-KeyFromConsulKv -key 'config/services/secrets/protocols/http/port'
        $vaultOptions = "-vault-addr=http://$($serviceName).service.$($domain):$($port) -vault-unwrap-token -vault-renew-token -vault-retry"
      }

      $startInfo.Arguments = "-config=""#{consul_template_config_path}"" $($vaultOptions)"

      Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') - Starting Consul-Template ... "
      Write-Output "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff') - Using arguments: $($startInfo.Arguments)"
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
  mode '755'
end

file "#{consul_template_bin_path}/#{service_exe_name}.xml" do
  content <<~XML
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
        <argument>"#{run_consul_template_script}"</argument>
        <stoptimeout>30sec</stoptimeout>

        <logpath>#{consul_template_logs_path}</logpath>
        <log mode="roll-by-size">
            <sizeThreshold>10240</sizeThreshold>
            <keepFiles>1</keepFiles>
        </log>
        <onfailure action="restart"/>
    </service>
  XML
  action :create
end

powershell_script 'consul_template_as_service' do
  code <<-POWERSHELL
    $ErrorActionPreference = 'Stop'

    $securePassword = ConvertTo-SecureString "#{service_password}" -AsPlainText -Force

    # Note the .\\ is to get the local machine account as per here:
    # http://stackoverflow.com/questions/313622/powershell-script-to-change-service-account#comment14535084_315616
    $credential = New-Object pscredential((".\\" + "#{service_username}"), $securePassword)

    $service = Get-Service -Name '#{service_name}' -ErrorAction SilentlyContinue
    if ($service -eq $null)
    {
        New-Service `
            -Name '#{service_name}' `
            -BinaryPathName '#{consul_template_bin_path}/#{service_exe_name}.exe' `
            -Credential $credential `
            -DisplayName '#{service_name}' `
            -StartupType Disabled
    }

    # Set the service to restart if it fails
    sc.exe failure #{service_name} reset=86400 actions=restart/5000
  POWERSHELL
end

# Create the event log source for the jenkins service. We'll create it now because the service runs as a normal user
# and is as such not allowed to create eventlog sources
registry_key "HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\services\\eventlog\\Application\\#{service_name}" do
  values [{
    name: 'EventMessageFile',
    type: :string,
    data: 'c:\\Windows\\Microsoft.NET\\Framework64\\v4.0.30319\\EventLogMessages.dll'
  }]
  action :create
end

#
# VAULT CONFIGURATION
#

file "#{consul_template_config_path}/consul_template_vault.hcl" do
  action :create
  content <<~HCL
    # This block defines the configuration for a template. Unlike other blocks,
    # this block may be specified multiple times to configure multiple templates.
    # It is also possible to configure templates via the CLI directly.
    template {
      # This option allows embedding the contents of a template in the configuration
      # file rather then supplying the `source` path to the template file. This is
      # useful for short templates. This option is mutually exclusive with the
      # `source` option.
      contents = "{{ $hostname := (env \\"COMPUTERNAME\\" | trimSpace | toLower ) }}{{ key (printf \\"auth/services/templates/%s/secrets\\" $hostname) }}"

      # This is the destination path on disk where the source template will render.
      # If the parent directories do not exist, Consul Template will attempt to
      # create them, unless create_dest_dirs is false.
      destination = "c:/users/#{service_username}/AppData/Local/Temp/consul_template_donotcare.txt"

      # This options tells Consul Template to create the parent directories of the
      # destination path if they do not exist. The default value is true.
      create_dest_dirs = false

      # This is the optional command to run when the template is rendered. The
      # command will only run if the resulting template changes. The command must
      # return within 30s (configurable), and it must have a successful exit code.
      # Consul Template is not a replacement for a process monitor or init system.
      command = "powershell.exe -noprofile -nologo -noninteractive -command \\"Restart-Service #{service_name}\\" "

      # This is the maximum amount of time to wait for the optional command to
      # return. Default is 30s.
      command_timeout = "90s"

      # Exit with an error when accessing a struct or map field/key that does not
      # exist. The default behavior will print "<no value>" when accessing a field
      # that does not exist. It is highly recommended you set this to "true" when
      # retrieving secrets from Vault.
      error_on_missing_key = false

      # This is the permission to render the file. If this option is left
      # unspecified, Consul Template will attempt to match the permissions of the
      # file that already exists at the destination path. If no file exists at that
      # path, the permissions are 0644.
      perms = 0755

      # This option backs up the previously rendered template at the destination
      # path before writing a new one. It keeps exactly one backup. This option is
      # useful for preventing accidental changes to the data without having a
      # rollback strategy.
      backup = false

      # These are the delimiters to use in the template. The default is "{{" and
      # "}}", but for some templates, it may be easier to use a different delimiter
      # that does not conflict with the output file itself.
      left_delimiter  = "{{"
      right_delimiter = "}}"

      # This is the `minimum(:maximum)` to wait before rendering a new template to
      # disk and triggering a command, separated by a colon (`:`). If the optional
      # maximum value is omitted, it is assumed to be 4x the required minimum value.
      # This is a numeric time with a unit suffix ("5s"). There is no default value.
      # The wait value for a template takes precedence over any globally-configured
      # wait.
      wait {
        min = "2s"
        max = "10s"
      }
    }
  HCL
  mode '755'
end
