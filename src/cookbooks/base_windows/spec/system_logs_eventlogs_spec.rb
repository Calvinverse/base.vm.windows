# frozen_string_literal: true

require 'spec_helper'

describe 'template_resource_windows_server_core::system_logs_eventlogs' do
  winlogbeat_config_path = 'c:/config/winlogbeat'
  winlogbeat_logs_path = 'c:/logs/winlogbeat'
  winlogbeat_bin_path = 'c:/ops/winlogbeat'

  context 'create the user to run the service with' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'creates the winlogbeat user' do
      expect(chef_run).to run_powershell_script('winlogbeat_user_with_password_that_does_not_expire')
    end
  end

  context 'create the log locations' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'creates the winlogbeat logs directory' do
      expect(chef_run).to create_directory(winlogbeat_logs_path)
    end
  end

  context 'create the winlogbeat locations' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'creates the winlogbeat config directory' do
      expect(chef_run).to create_directory(winlogbeat_config_path)
    end

    it 'creates the winlogbeat bin directory' do
      expect(chef_run).to create_directory(winlogbeat_bin_path)
    end

    it 'creates winlogbeat.exe in the winlogbeat ops directory' do
      expect(chef_run).to create_remote_file("#{winlogbeat_bin_path}/winlogbeat.exe")
    end
  end

  context 'install winlogbeat as service' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'installs winlogbeat as service' do
      expect(chef_run).to run_powershell_script('winlogbeat_as_service')
    end
  end

  context 'create the consul-template files for winlogbeat' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    winlogbeat_config_content = <<~CONF
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
    it 'creates winlogbeat template file in the consul-template template directory' do
      expect(chef_run).to create_file('c:/config/consul-template/templates/winlogbeat.ctmpl')
        .with_content(winlogbeat_config_content)
    end

    consul_template_winlogbeat_content = <<~CONF
      # This block defines the configuration for a template. Unlike other blocks,
      # this block may be specified multiple times to configure multiple templates.
      # It is also possible to configure templates via the CLI directly.
      template {
        # This is the source file on disk to use as the input template. This is often
        # called the "Consul Template template". This option is required if not using
        # the `contents` option.
        source = "c:/config/consul-template/templates/winlogbeat.ctmpl"

        # This is the destination path on disk where the source template will render.
        # If the parent directories do not exist, Consul Template will attempt to
        # create them, unless create_dest_dirs is false.
        destination = "#{winlogbeat_config_path}/winlogbeat.yml"

        # This options tells Consul Template to create the parent directories of the
        # destination path if they do not exist. The default value is true.
        create_dest_dirs = false

        # This is the optional command to run when the template is rendered. The
        # command will only run if the resulting template changes. The command must
        # return within 30s (configurable), and it must have a successful exit code.
        # Consul Template is not a replacement for a process monitor or init system.
        command = "powershell.exe -noprofile -nologo -noninteractive -command \\"if ((Get-Service -Name winlogbeat).Status -ne 'Running'){ Start-Service winlogbeat }\\" "

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
    CONF
    it 'creates winlogbeat.hcl in the consul-template template directory' do
      expect(chef_run).to create_file('c:/config/consul-template/config/winlogbeat.hcl')
        .with_content(consul_template_winlogbeat_content)
    end
  end
end
