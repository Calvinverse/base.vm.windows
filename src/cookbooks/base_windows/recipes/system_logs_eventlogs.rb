# frozen_string_literal: true

#
# Cookbook Name:: template_resource_windows_server_core
# Recipe:: system_logs
#
# Copyright 2019, Vista Entertainment
#

# Consul-Template paths
consul_template_template_path = node['consul_template']['template_path']
consul_template_config_path = node['consul_template']['config_path']

#
# USERS
#

# Configure the service user under which winlogbeat will be run
service_username = node['winlogbeat']['service']['user_name']
service_password = node['winlogbeat']['service']['user_password']

# Configure the service user under which winlogbeat will be run
# Make sure that the user password doesn't expire. The password is a random GUID, so it is unlikely that
# it will ever be guessed.
powershell_script 'winlogbeat_user_with_password_that_does_not_expire' do
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

# Grant the user the LogOnAsService permission. Following this answer on SO: http://stackoverflow.com/a/21235462/539846
# With some additional bug fixes to get the correct line from the export file and to put the correct text in the import file
powershell_script 'winlogbeat_user_grant_service_logon_rights' do
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
# DIRECTORIES
#

service_name = node['winlogbeat']['service']['name']

bin_path = "#{node['paths']['ops']}/#{service_name}"
config_path = node['winlogbeat']['config_directory']
%W[#{bin_path} #{config_path}].each do |path|
  directory path do
    action :create
    inherits false
    rights :read_execute, service_username, applies_to_children: true, applies_to_self: true
    rights :full_control, 'Administrators', applies_to_children: true
  end
end

logs_path = "#{node['paths']['logs']}/#{service_name}"
directory logs_path do
  action :create
  rights :modify, service_username, applies_to_children: true, applies_to_self: false
end

winlogbeat_exe = 'winlogbeat.exe'
winlogbeat_exe_path = "#{bin_path}/#{winlogbeat_exe}"
remote_file winlogbeat_exe_path do
  action :create
  source node['winlogbeat']['url']
end

#
# SERVICE
#

config_file = node['winlogbeat']['config_file_path']
powershell_script 'winlogbeat_as_service' do
  code <<~POWERSHELL
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
            -BinaryPathName '#{winlogbeat_exe_path} --c "#{config_file}" --path.home "#{bin_path}" --path.data "C:/ProgramData/winlogbeat" --path.logs "#{logs_path}" ' `
            -Credential $credential `
            -DisplayName '#{service_name}' `
            -StartupType Automatic
    }

    # Set the service to restart if it fails
    # sc.exe failure #{service_name} reset=86400 actions=restart/5000
  POWERSHELL
end

#
# CONFIGURATION
#

# The configuration file for winlogbeat is dropped in the configuration path
# when the resource is provisioned because it contains environment specific information
winlogbeat_template_file = node['winlogbeat']['consul_template_file']
file "#{consul_template_template_path}/#{winlogbeat_template_file}" do
  action :create
  content <<~CONF
    ###################### Winlogbeat Configuration Example ##########################

    #======================= Winlogbeat specific options ==========================

    # event_logs specifies a list of event logs to monitor as well as any
    # accompanying options. The YAML data type of event_logs is a list of
    # dictionaries.
    #
    # The supported keys are name (required), tags, fields, fields_under_root,
    # forwarded, ignore_older, level, event_id, provider, and include_xml. Please
    # visit the documentation for the complete details of each option.
    # https://go.es.io/WinlogbeatConfig
    winlogbeat.event_logs:
      - name: Application
        ignore_older: 72h
      - name: Security
      - name: System

    #================================ General =====================================

    # The name of the shipper that publishes the network data. It can be used to group
    # all the transactions sent by a single shipper in the web interface.
    #name:

    # The tags of the shipper are included in their own field with each
    # transaction published.
    #tags: ["service-X", "web-tier"]

    # Optional fields that you can specify to add additional information to the
    # output.
    fields:
      environment: "{{ keyOrDefault "config/services/consul/datacenter" "unknown" }}"
      category: "{{ env "RESOURCE_SHORT_NAME" | toLower }}"

    #================================ Outputs =====================================

    # Configure what output to use when sending the data collected by the beat.

    #------------------------------ MQTT output -----------------------------------
    output.mqtt:
      host: "{{ keyOrDefault "config/services/queue/protocols/mqtt/host" "unknown" }}.service.{{ keyOrDefault "config/services/consul/domain" "unknown" }}"
      port: {{ keyOrDefault "config/services/queue/protocols/mqtt/port" "1883" }}
      topic: "{{ keyOrDefault "config/services/queue/logs/eventlog/queue" "unknown" }}"
      {{ with secret "secret/services/queue/users/logs/eventlog" }}
        {{ if .Data.password }}
      user: "{{ keyOrDefault "config/services/queue/logs/eventlog/vhost" "unknown" }}:{{ .Data.username }}"
      password: "{{ .Data.password }}"
        {{ end }}
      {{ end }}

    #================================ Logging =====================================

    # Sets log level. The default log level is info.
    # Available log levels are: error, warning, info, debug
    logging.level: debug

    # At debug level, you can selectively enable logging only for some components.
    # To enable all selectors use ["*"]. Examples of other selectors are "beat",
    # "publish", "service".
    #logging.selectors: ["*"]

    #============================== Xpack Monitoring ===============================
    # winlogbeat can export internal metrics to a central Elasticsearch monitoring
    # cluster.  This requires xpack monitoring to be enabled in Elasticsearch.  The
    # reporting is disabled by default.

    # Set to true to enable the monitoring reporter.
    #xpack.monitoring.enabled: false

    # Uncomment to send the metrics to Elasticsearch. Most settings from the
    # Elasticsearch output are accepted here as well. Any setting that is not set is
    # automatically inherited from the Elasticsearch output configuration, so if you
    # have the Elasticsearch output configured, you can simply uncomment the
    # following line.
    #xpack.monitoring.elasticsearch:
  CONF
end

# Create the consul-template configuration file
file "#{consul_template_config_path}/winlogbeat.hcl" do
  action :create
  content <<~HCL
    # This block defines the configuration for a template. Unlike other blocks,
    # this block may be specified multiple times to configure multiple templates.
    # It is also possible to configure templates via the CLI directly.
    template {
      # This is the source file on disk to use as the input template. This is often
      # called the "Consul Template template". This option is required if not using
      # the `contents` option.
      source = "#{consul_template_template_path}/#{winlogbeat_template_file}"

      # This is the destination path on disk where the source template will render.
      # If the parent directories do not exist, Consul Template will attempt to
      # create them, unless create_dest_dirs is false.
      destination = "#{config_file}"

      # This options tells Consul Template to create the parent directories of the
      # destination path if they do not exist. The default value is true.
      create_dest_dirs = false

      # This is the optional command to run when the template is rendered. The
      # command will only run if the resulting template changes. The command must
      # return within 30s (configurable), and it must have a successful exit code.
      # Consul Template is not a replacement for a process monitor or init system.
      command = "powershell.exe -noprofile -nologo -noninteractive -command \\"if ((Get-Service -Name #{service_name}).Status -ne 'Running'){ Start-Service #{service_name} }\\" "

      # This is the maximum amount of time to wait for the optional command to
      # return. Default is 30s.
      command_timeout = "15s"

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
      backup = true

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
end
