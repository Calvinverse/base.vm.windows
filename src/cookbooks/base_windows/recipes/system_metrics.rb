# frozen_string_literal: true

#
# Cookbook Name:: base_windows
# Recipe:: system_metrics
#
# Copyright 2018, P. van der Velde
#

# Configure the service user under which consul will be run
service_username = node['telegraf']['service']['user_name']
service_password = node['telegraf']['service']['user_password']

# Configure the service user under which consul-template will be run
# Make sure that the user password doesn't expire. The password is a random GUID, so it is unlikely that
# it will ever be guessed. And the user is a normal user who can't do anything so we don't really care about it
powershell_script 'telegraf_user_with_password_that_does_not_expire' do
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
      -Group 'Performance Monitor Users' `
      -Member $localUser.Name `
      -Verbose
  POWERSHELL
end

# Grant the user the LogOnAsService permission. Following this anwer on SO: http://stackoverflow.com/a/21235462/539846
# With some additional bug fixes to get the correct line from the export file and to put the correct text in the import file
powershell_script 'telegraf_user_grant_service_logon_rights' do
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
# INSTALL TELEGRAF
#

service_name = node['telegraf']['service']['name']

telegraf_bin_path = "#{node['paths']['ops']}/#{service_name}"
telegraf_config_path = "#{node['paths']['config']}/#{service_name}"
%W[#{telegraf_bin_path} #{telegraf_config_path}].each do |path|
  directory path do
    action :create
    rights :read_execute, 'Everyone', applies_to_children: true, applies_to_self: false
  end
end

telegraf_logs_path = "#{node['paths']['logs']}/#{service_name}"
directory telegraf_logs_path do
  action :create
  rights :modify, service_username, applies_to_children: true, applies_to_self: false
end

telegraf_exe = 'telegraf.exe'
telegraf_zip_path = "#{node['paths']['temp']}/telegraf.zip"
remote_file telegraf_zip_path do
  action :create
  checksum node['telegraf']['shasums']
  source node['telegraf']['download_urls']
end

seven_zip_archive node['paths']['ops'] do
  overwrite true
  source telegraf_zip_path
  timeout 30
end

#
# WINDOWS SERVICE
#

service_name = node['telegraf']['service']['name']
telegraf_config_file = node['telegraf']['config_file_path']
telegraf_config_directory = node['telegraf']['config_directory']
powershell_script 'telegraf_as_service' do
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
            -BinaryPathName '#{telegraf_bin_path}/#{telegraf_exe} --config "#{telegraf_config_file}" --config-directory "#{telegraf_config_directory}"' `
            -Credential $credential `
            -DisplayName '#{service_name}' `
            -StartupType Automatic
    }

    # Set the service to restart if it fails
    # sc.exe failure #{service_name} reset=86400 actions=restart/5000
  POWERSHELL
end

#
# ALLOW TELEGRAF THROUGH THE FIREWALL
#

telegraf_statsd_port = node['telegraf']['statsd']['port']
firewall_rule 'telegraf-statsd' do
  command :allow
  description 'Allow Telegraf statsd traffic'
  dest_port telegraf_statsd_port
  direction :in
end

#
# DEFAULT CONFIGURATION
#

consul_template_template_path = node['consul_template']['template_path']
consul_template_config_path = node['consul_template']['config_path']

unbound_bin_path = "#{node['paths']['ops']}/#{node['unbound']['service']['name']}"

# The configuration file for telegraf is dropped in the configuration path
# when the resource is provisioned because it contains environment specific information
telegraf_template_file = node['telegraf']['consul_template_file']
file "#{consul_template_template_path}/#{telegraf_template_file}" do
  action :create
  content <<~CONF
    # Telegraf Configuration

    # Global tags can be specified here in key="value" format.
    [global_tags]
      environment = "{{ keyOrDefault "config/services/consul/datacenter" "unknown" }}"
      os = "windows"
      consul = "{{ env "CONSUL_SERVER_OR_CLIENT" | toLower }}"
      category = "{{ env "RESOURCE_SHORT_NAME" | toLower }}"

    # Configuration for telegraf agent
    [agent]
      ## Default data collection interval for all inputs
      interval = "10s"

      ## Rounds collection interval to 'interval'
      ## ie, if interval="10s" then always collect on :00, :10, :20, etc.
      round_interval = true

      ## Telegraf will send metrics to outputs in batches of at most
      ## metric_batch_size metrics.
      ## This controls the size of writes that Telegraf sends to output plugins.
      metric_batch_size = 1000

      ## For failed writes, telegraf will cache metric_buffer_limit metrics for each
      ## output, and will flush this buffer on a successful write. Oldest metrics
      ## are dropped first when this buffer fills.
      ## This buffer only fills when writes fail to output plugin(s).
      metric_buffer_limit = 10000

      ## Collection jitter is used to jitter the collection by a random amount.
      ## Each plugin will sleep for a random time within jitter before collecting.
      ## This can be used to avoid many plugins querying things like sysfs at the
      ## same time, which can have a measurable effect on the system.
      collection_jitter = "0s"

      ## Default flushing interval for all outputs. You shouldn't set this below
      ## interval. Maximum flush_interval will be flush_interval + flush_jitter
      flush_interval = "10s"
      ## Jitter the flush interval by a random amount. This is primarily to avoid
      ## large write spikes for users running a large number of telegraf instances.
      ## ie, a jitter of 5s and interval 10s means flushes will happen every 10-15s
      flush_jitter = "0s"

      ## By default or when set to "0s", precision will be set to the same
      ## timestamp order as the collection interval, with the maximum being 1s.
      ##   ie, when interval = "10s", precision will be "1s"
      ##       when interval = "250ms", precision will be "1ms"
      ## Precision will NOT be used for service inputs. It is up to each individual
      ## service input to set the timestamp at the appropriate precision.
      ## Valid time units are "ns", "us" (or "µs"), "ms", "s".
      precision = ""

      ## Logging configuration:
      ## Run telegraf with debug log messages.
      debug = false
      ## Run telegraf in quiet mode (error log messages only).
      quiet = false
      ## Specify the log file name. The empty string means to log to stderr.
      logfile = "#{telegraf_logs_path}/telegraf.log"

      ## Override default hostname, if empty use os.Hostname()
      hostname = ""
      ## If set to true, do no set the "host" tag in the telegraf agent.
      omit_hostname = false

    ###############################################################################
    #                            INPUT PLUGINS                                    #
    ###############################################################################

    [[inputs.win_perf_counters]]
      [inputs.win_perf_counters.tags]
      influxdb_database = "system"

      [[inputs.win_perf_counters.object]]
        # Processor usage, alternative to native, reports on a per core.
        ObjectName = "Processor"
        Instances = ["*"]
        Counters = [
          "% Idle Time",
          "% Interrupt Time",
          "% Privileged Time",
          "% User Time",
          "% Processor Time",
          "% DPC Time",
        ]
        Measurement = "cpu"
        # Set to true to include _Total instance when querying for all (*).
        IncludeTotal=true

      [[inputs.win_perf_counters.object]]
        # Disk times and queues
        ObjectName = "LogicalDisk"
        Instances = ["*"]
        Counters = [
          "% Idle Time",
          "% Disk Time",
          "% Disk Read Time",
          "% Disk Write Time",
          "Current Disk Queue Length",
          "% Free Space",
          "Free Megabytes",
        ]
        Measurement = "disk"
        # Set to true to include _Total instance when querying for all (*).
        #IncludeTotal=false

      [[inputs.win_perf_counters.object]]
        ObjectName = "PhysicalDisk"
        Instances = ["*"]
        Counters = [
          "Disk Read Bytes/sec",
          "Disk Write Bytes/sec",
          "Current Disk Queue Length",
          "Disk Reads/sec",
          "Disk Writes/sec",
          "% Disk Time",
          "% Disk Read Time",
          "% Disk Write Time",
        ]
        Measurement = "diskio"

      [[inputs.win_perf_counters.object]]
        ObjectName = "Network Interface"
        Instances = ["*"]
        Counters = [
          "Bytes Received/sec",
          "Bytes Sent/sec",
          "Packets Received/sec",
          "Packets Sent/sec",
          "Packets Received Discarded",
          "Packets Outbound Discarded",
          "Packets Received Errors",
          "Packets Outbound Errors",
        ]
        Measurement = "net"

      [[inputs.win_perf_counters.object]]
        ObjectName = "System"
        Counters = [
          "Context Switches/sec",
          "System Calls/sec",
          "Processor Queue Length",
          "System Up Time",
        ]
        Instances = ["------"]
        Measurement = "system"
        # Set to true to include _Total instance when querying for all (*).
        #IncludeTotal=false

      [[inputs.win_perf_counters.object]]
        # Example query where the Instance portion must be removed to get data back,
        # such as from the Memory object.
        ObjectName = "Memory"
        Counters = [
          "Available Bytes",
          "Cache Faults/sec",
          "Demand Zero Faults/sec",
          "Page Faults/sec",
          "Pages/sec",
          "Transition Faults/sec",
          "Pool Nonpaged Bytes",
          "Pool Paged Bytes",
          "Standby Cache Reserve Bytes",
          "Standby Cache Normal Priority Bytes",
          "Standby Cache Core Bytes",
        ]
        # Use 6 x - to remove the Instance bit from the query.
        Instances = ["------"]
        Measurement = "mem"
        # Set to true to include _Total instance when querying for all (*).
        #IncludeTotal=false

      [[inputs.win_perf_counters.object]]
        # Example query where the Instance portion must be removed to get data back,
        # such as from the Paging File object.
        ObjectName = "Paging File"
        Counters = [
          "% Usage",
        ]
        Instances = ["_Total"]
        Measurement = "swap"

      [[inputs.win_perf_counters.object]]
        ObjectName = "Network Interface"
        Instances = ["*"]
        Counters = [
          "Bytes Sent/sec",
          "Bytes Received/sec",
          "Packets Sent/sec",
          "Packets Received/sec",
          "Packets Received Discarded",
          "Packets Received Errors",
          "Packets Outbound Discarded",
          "Packets Outbound Errors",
        ]


    # # A plugin to collect stats from Unbound - a validating, recursive, and caching DNS resolver
    [[inputs.unbound]]
      ## If running as a restricted user you can prepend sudo for additional access:
      # use_sudo = false

      ## The default location of the unbound-control binary can be overridden with:
      binary = "#{unbound_bin_path}/unbound-control"

      ## The default timeout of 1s can be overriden with:
      # timeout = "1s"

      ## Use the builtin fielddrop/fieldpass telegraf filters in order to keep/remove specific fields
      # fieldpass = ["total_*", "num_*","time_up", "mem_*"]
      [inputs.unbound.tags]
        influxdb_database = "system"


    # Statsd UDP/TCP Server
    [[inputs.statsd]]
      ## Protocol, must be "tcp", "udp", "udp4" or "udp6" (default=udp)
      # protocol = "udp"

      ## MaxTCPConnection - applicable when protocol is set to tcp (default=250)
      # max_tcp_connections = 250

      ## Address and port to host UDP listener on
      service_address = ":#{telegraf_statsd_port}"

      ## The following configuration options control when telegraf clears it's cache
      ## of previous values. If set to false, then telegraf will only clear it's
      ## cache when the daemon is restarted.
      ## Reset gauges every interval (default=true)
      delete_gauges = true
      ## Reset counters every interval (default=true)
      delete_counters = true
      ## Reset sets every interval (default=true)
      delete_sets = true
      ## Reset timings & histograms every interval (default=true)
      delete_timings = true

      ## Percentiles to calculate for timing & histogram stats
      percentiles = [90]

      ## separator to use between elements of a statsd metric
      metric_separator = "_"

      ## Parses tags in the datadog statsd format
      ## http://docs.datadoghq.com/guides/dogstatsd/
      parse_data_dog_tags = false

      ## Statsd data translation templates, more info can be read here:
      ## https://github.com/influxdata/telegraf/blob/master/docs/DATA_FORMATS_INPUT.md#graphite
      templates = [
    {{ range $service := (env "STATSD_ENABLED_SERVICES" | split ";") }}
      {{ if keyExists (printf "config/services/%s/metrics/statsd/rules" $service) }}
        {{ key (printf "config/services/%s/metrics/statsd/rules" $service) | indent 4 }}
      {{ end }}
    {{ end }}
      ]

      ## Number of UDP messages allowed to queue up, once filled,
      ## the statsd server will start dropping packets
      allowed_pending_messages = 10000

      ## Number of timing/histogram values to track per-measurement in the
      ## calculation of percentiles. Raising this limit increases the accuracy
      ## of percentiles but also increases the memory usage and cpu time.
      # percentile_limit = 1000
      [inputs.statsd.tags]
        influxdb_database = "statsd"

    ###############################################################################
    #                            OUTPUT PLUGINS                                   #
    ###############################################################################

    {{ if keyExists "config/services/metrics/protocols/http/host" }}
    # Configuration for influxdb server to send metrics to
    [[outputs.influxdb]]
      ## The full HTTP or UDP URL for your InfluxDB instance.
      ##
      ## Multiple urls can be specified as part of the same cluster,
      ## this means that only ONE of the urls will be written to each interval.
      # urls = ["udp://127.0.0.1:8089"] # UDP endpoint example
      urls = ["http://{{ keyOrDefault "config/services/metrics/protocols/http/host" "unknown" }}.service.{{ keyOrDefault "config/services/consul/domain" "unknown" }}:{{ keyOrDefault "config/services/metrics/protocols/http/port" "80" }}"]
      ## The target database for metrics (telegraf will create it if not exists).
      database = "{{ keyOrDefault "config/services/metrics/databases/system" "system" }}" # required

      ## Name of existing retention policy to write to.  Empty string writes to
      ## the default retention policy.
      retention_policy = ""
      ## Write consistency (clusters only), can be: "any", "one", "quorum", "all"
      write_consistency = "any"

      ## Write timeout (for the InfluxDB client), formatted as a string.
      ## If not provided, will default to 5s. 0s means no timeout (not recommended).
      timeout = "5s"
      # username = "telegraf"
      # password = "metricsmetricsmetricsmetrics"
      ## Set the user agent for HTTP POSTs (can be useful for log differentiation)
      user_agent = "telegraf"
      ## Set UDP payload size, defaults to InfluxDB UDP Client default (512 bytes)
      # udp_payload = 512

      ## Optional SSL Config
      # ssl_ca = "/etc/telegraf/ca.pem"
      # ssl_cert = "/etc/telegraf/cert.pem"
      # ssl_key = "/etc/telegraf/key.pem"
      ## Use SSL but skip chain & host verification
      # insecure_skip_verify = false

      ## HTTP Proxy Config
      # http_proxy = "http://corporate.proxy:3128"

      ## Optional HTTP headers
      # http_headers = {"X-Special-Header" = "Special-Value"}

      ## Compress each HTTP request payload using GZIP.
      # content_encoding = "gzip"
      [outputs.influxdb.tagpass]
        influxdb_database = ["system"]

    # Configuration for influxdb server to send metrics to
    [[outputs.influxdb]]
      ## The full HTTP or UDP URL for your InfluxDB instance.
      ##
      ## Multiple urls can be specified as part of the same cluster,
      ## this means that only ONE of the urls will be written to each interval.
      # urls = ["udp://127.0.0.1:8089"] # UDP endpoint example
      urls = ["http://{{ keyOrDefault "config/services/metrics/protocols/http/host" "unknown" }}.service.{{ keyOrDefault "config/services/consul/domain" "unknown" }}:{{ keyOrDefault "config/services/metrics/protocols/http/port" "80" }}"]
      ## The target database for metrics (telegraf will create it if not exists).
      database = "{{ keyOrDefault "config/services/metrics/databases/statsd" "statsd" }}" # required

      ## Name of existing retention policy to write to.  Empty string writes to
      ## the default retention policy.
      retention_policy = ""
      ## Write consistency (clusters only), can be: "any", "one", "quorum", "all"
      write_consistency = "any"

      ## Write timeout (for the InfluxDB client), formatted as a string.
      ## If not provided, will default to 5s. 0s means no timeout (not recommended).
      timeout = "5s"
      # username = "telegraf"
      # password = "metricsmetricsmetricsmetrics"
      ## Set the user agent for HTTP POSTs (can be useful for log differentiation)
      user_agent = "telegraf"
      ## Set UDP payload size, defaults to InfluxDB UDP Client default (512 bytes)
      # udp_payload = 512

      ## Optional SSL Config
      # ssl_ca = "/etc/telegraf/ca.pem"
      # ssl_cert = "/etc/telegraf/cert.pem"
      # ssl_key = "/etc/telegraf/key.pem"
      ## Use SSL but skip chain & host verification
      # insecure_skip_verify = false

      ## HTTP Proxy Config
      # http_proxy = "http://corporate.proxy:3128"

      ## Optional HTTP headers
      # http_headers = {"X-Special-Header" = "Special-Value"}

      ## Compress each HTTP request payload using GZIP.
      # content_encoding = "gzip"
      [outputs.influxdb.tagpass]
        influxdb_database = ["statsd"]

    # Configuration for influxdb server to send metrics to
    [[outputs.influxdb]]
      ## The full HTTP or UDP URL for your InfluxDB instance.
      ##
      ## Multiple urls can be specified as part of the same cluster,
      ## this means that only ONE of the urls will be written to each interval.
      # urls = ["udp://127.0.0.1:8089"] # UDP endpoint example
      urls = ["http://{{ keyOrDefault "config/services/metrics/protocols/http/host" "unknown" }}.service.{{ keyOrDefault "config/services/consul/domain" "unknown" }}:{{ keyOrDefault "config/services/metrics/protocols/http/port" "80" }}"]
      ## The target database for metrics (telegraf will create it if not exists).
      database = "{{ keyOrDefault "config/services/metrics/databases/services" "services" }}" # required

      ## Name of existing retention policy to write to.  Empty string writes to
      ## the default retention policy.
      retention_policy = ""
      ## Write consistency (clusters only), can be: "any", "one", "quorum", "all"
      write_consistency = "any"

      ## Write timeout (for the InfluxDB client), formatted as a string.
      ## If not provided, will default to 5s. 0s means no timeout (not recommended).
      timeout = "5s"
      # username = "telegraf"
      # password = "metricsmetricsmetricsmetrics"
      ## Set the user agent for HTTP POSTs (can be useful for log differentiation)
      user_agent = "telegraf"
      ## Set UDP payload size, defaults to InfluxDB UDP Client default (512 bytes)
      # udp_payload = 512

      ## Optional SSL Config
      # ssl_ca = "/etc/telegraf/ca.pem"
      # ssl_cert = "/etc/telegraf/cert.pem"
      # ssl_key = "/etc/telegraf/key.pem"
      ## Use SSL but skip chain & host verification
      # insecure_skip_verify = false

      ## HTTP Proxy Config
      # http_proxy = "http://corporate.proxy:3128"

      ## Optional HTTP headers
      # http_headers = {"X-Special-Header" = "Special-Value"}

      ## Compress each HTTP request payload using GZIP.
      # content_encoding = "gzip"
      [outputs.influxdb.tagpass]
        influxdb_database = ["services"]
    {{ else }}
    # Send metrics to nowhere at all
    [[outputs.discard]]
      # no configuration
    {{ end }}
  CONF
  mode '755'
end

# Create the consul-template configuration file
file "#{consul_template_config_path}/telegraf.hcl" do
  action :create
  content <<~HCL
    # This block defines the configuration for a template. Unlike other blocks,
    # this block may be specified multiple times to configure multiple templates.
    # It is also possible to configure templates via the CLI directly.
    template {
      # This is the source file on disk to use as the input template. This is often
      # called the "Consul Template template". This option is required if not using
      # the `contents` option.
      source = "#{consul_template_template_path}/#{telegraf_template_file}"

      # This is the destination path on disk where the source template will render.
      # If the parent directories do not exist, Consul Template will attempt to
      # create them, unless create_dest_dirs is false.
      destination = "#{telegraf_config_file}"

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
  mode '755'
end
