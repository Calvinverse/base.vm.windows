# frozen_string_literal: true

require 'spec_helper'

describe 'template_resource_windows_server_core::system_logs_filelogs' do
  logs_path = 'c:/logs'
  filebeat_config_path = 'c:/config/filebeat'
  filebeat_logs_path = 'c:/logs/filebeat'
  filebeat_bin_path = 'c:/ops/filebeat'

  context 'create the user to run the service with' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'creates the filebeat user' do
      expect(chef_run).to run_powershell_script('filebeat_user_with_password_that_does_not_expire')
    end
  end

  context 'create the log locations' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'creates the filebeat logs directory' do
      expect(chef_run).to create_directory(filebeat_logs_path)
    end
  end

  context 'create the filebeat locations' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'creates the filebeat config directory' do
      expect(chef_run).to create_directory(filebeat_config_path)
    end

    it 'creates the filebeat bin directory' do
      expect(chef_run).to create_directory(filebeat_bin_path)
    end

    it 'creates filebeat.exe in the filebeat ops directory' do
      expect(chef_run).to create_remote_file("#{filebeat_bin_path}/filebeat.exe")
    end
  end

  context 'install filebeat as service' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'installs filebeat as service' do
      expect(chef_run).to run_powershell_script('filebeat_as_service')
    end
  end

  context 'create the consul-template files for filebeat' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    filebeat_config_content = <<~CONF
      ######################## Filebeat Configuration ############################

      #=========================== Filebeat inputs =============================

      # List of inputs to fetch data.
      filebeat.inputs:
      # Each - is an input. Most options can be set at the input level, so
      # you can use different inputs for various configurations.
      # Below are the input specific configurations.

      # Type of the files. Based on this the way the file is read is decided.
      # The different types cannot be mixed in one input
      #
      # Possible options are:
      # * log: Reads every line of the log file (default)
      # * stdin: Reads the standard in

      #------------------------------ Log input --------------------------------
      - type: log

        # Change to true to enable this input configuration.
        enabled: true

        # Paths that should be crawled and fetched. Glob based paths.
        # To fetch all ".log" files from a specific level of subdirectories
        # /var/log/*/*.log can be used.
        # For each file found under this path, a harvester is started.
        # Make sure not file is defined twice as this can lead to unexpected behaviour.
        paths:
          - #{logs_path}/*/*.log
          - #{filebeat_logs_path}/filebeat

        # Configure the file encoding for reading files with international characters
        # following the W3C recommendation for HTML5 (http://www.w3.org/TR/encoding).
        # Some sample encodings:
        #   plain, utf-8, utf-16be-bom, utf-16be, utf-16le, big5, gb18030, gbk,
        #    hz-gb-2312, euc-kr, euc-jp, iso-2022-jp, shift-jis, ...
        #encoding: plain

        # Exclude lines. A list of regular expressions to match. It drops the lines that are
        # matching any regular expression from the list. The include_lines is called before
        # exclude_lines. By default, no lines are dropped.
        #exclude_lines: ['^DBG']

        # Include lines. A list of regular expressions to match. It exports the lines that are
        # matching any regular expression from the list. The include_lines is called before
        # exclude_lines. By default, all the lines are exported.
        #include_lines: ['^ERR', '^WARN']

        # Exclude files. A list of regular expressions to match. Filebeat drops the files that
        # are matching any regular expression from the list. By default, no files are dropped.
        exclude_files: ['.gz$']

        # Optional additional fields. These fields can be freely picked
        # to add additional information to the crawled log files for filtering
        #fields:
        #  level: debug
        #  review: 1

        # Set to true to store the additional fields as top level fields instead
        # of under the "fields" sub-dictionary. In case of name conflicts with the
        # fields added by Filebeat itself, the custom fields overwrite the default
        # fields.
        #fields_under_root: false

        # Ignore files which were modified more then the defined timespan in the past.
        # ignore_older is disabled by default, so no files are ignored by setting it to 0.
        # Time strings like 2h (2 hours), 5m (5 minutes) can be used.
        #ignore_older: 0

        # How often the input checks for new files in the paths that are specified
        # for harvesting. Specify 1s to scan the directory as frequently as possible
        # without causing Filebeat to scan too frequently. Default: 10s.
        #scan_frequency: 10s

        # Defines the buffer size every harvester uses when fetching the file
        #harvester_buffer_size: 16384

        # Maximum number of bytes a single log event can have
        # All bytes after max_bytes are discarded and not sent. The default is 10MB.
        # This is especially useful for multiline log messages which can get large.
        #max_bytes: 10485760

        ### Recursive glob configuration

        # Expand "**" patterns into regular glob patterns.
        recursive_glob.enabled: true

        ### JSON configuration

        # Decode JSON options. Enable this if your logs are structured in JSON.
        # JSON key on which to apply the line filtering and multiline settings. This key
        # must be top level and its value must be string, otherwise it is ignored. If
        # no text key is defined, the line filtering and multiline features cannot be used.
        #json.message_key:

        # By default, the decoded JSON is placed under a "json" key in the output document.
        # If you enable this setting, the keys are copied top level in the output document.
        #json.keys_under_root: false

        # If keys_under_root and this setting are enabled, then the values from the decoded
        # JSON object overwrite the fields that Filebeat normally adds (type, source, offset, etc.)
        # in case of conflicts.
        #json.overwrite_keys: false

        # If this setting is enabled, Filebeat adds a "error.message" and "error.key: json" key in case of JSON
        # unmarshaling errors or when a text key is defined in the configuration but cannot
        # be used.
        #json.add_error_key: false

        ### Multiline options

        # Mutiline can be used for log messages spanning multiple lines. This is common
        # for Java Stack Traces or C-Line Continuation

        # The regexp Pattern that has to be matched. The example pattern matches all lines starting with [
        #multiline.pattern: ^\[

        # Defines if the pattern set under pattern should be negated or not. Default is false.
        #multiline.negate: false

        # Match can be set to "after" or "before". It is used to define if lines should be append to a pattern
        # that was (not) matched before or after or as long as a pattern is not matched based on negate.
        # Note: After is the equivalent to previous and before is the equivalent to to next in Logstash
        #multiline.match: after

        # The maximum number of lines that are combined to one event.
        # In case there are more the max_lines the additional lines are discarded.
        # Default is 500
        #multiline.max_lines: 500

        # After the defined timeout, an multiline event is sent even if no new pattern was found to start a new event
        # Default is 5s.
        #multiline.timeout: 5s

        # Setting tail_files to true means filebeat starts reading new files at the end
        # instead of the beginning. If this is used in combination with log rotation
        # this can mean that the first entries of a new file are skipped.
        #tail_files: false

        # The Ingest Node pipeline ID associated with this input. If this is set, it
        # overwrites the pipeline option from the Elasticsearch output.
        #pipeline:

        # If symlinks is enabled, symlinks are opened and harvested. The harvester is openening the
        # original for harvesting but will report the symlink name as source.
        #symlinks: false

        # Backoff values define how aggressively filebeat crawls new files for updates
        # The default values can be used in most cases. Backoff defines how long it is waited
        # to check a file again after EOF is reached. Default is 1s which means the file
        # is checked every second if new lines were added. This leads to a near real time crawling.
        # Every time a new line appears, backoff is reset to the initial value.
        #backoff: 1s

        # Max backoff defines what the maximum backoff time is. After having backed off multiple times
        # from checking the files, the waiting time will never exceed max_backoff independent of the
        # backoff factor. Having it set to 10s means in the worst case a new line can be added to a log
        # file after having backed off multiple times, it takes a maximum of 10s to read the new line
        #max_backoff: 10s

        # The backoff factor defines how fast the algorithm backs off. The bigger the backoff factor,
        # the faster the max_backoff value is reached. If this value is set to 1, no backoff will happen.
        # The backoff value will be multiplied each time with the backoff_factor until max_backoff is reached
        #backoff_factor: 2

        # Max number of harvesters that are started in parallel.
        # Default is 0 which means unlimited
        #harvester_limit: 0

        ### Harvester closing options

        # Close inactive closes the file handler after the predefined period.
        # The period starts when the last line of the file was, not the file ModTime.
        # Time strings like 2h (2 hours), 5m (5 minutes) can be used.
        #close_inactive: 5m

        # Close renamed closes a file handler when the file is renamed or rotated.
        # Note: Potential data loss. Make sure to read and understand the docs for this option.
        #close_renamed: false

        # When enabling this option, a file handler is closed immediately in case a file can't be found
        # any more. In case the file shows up again later, harvesting will continue at the last known position
        # after scan_frequency.
        #close_removed: true

        # Closes the file handler as soon as the harvesters reaches the end of the file.
        # By default this option is disabled.
        # Note: Potential data loss. Make sure to read and understand the docs for this option.
        #close_eof: false

        ### State options

        # Files for the modification data is older then clean_inactive the state from the registry is removed
        # By default this is disabled.
        #clean_inactive: 0

        # Removes the state for file which cannot be found on disk anymore immediately
        #clean_removed: true

        # Close timeout closes the harvester after the predefined time.
        # This is independent if the harvester did finish reading the file or not.
        # By default this option is disabled.
        # Note: Potential data loss. Make sure to read and understand the docs for this option.
        #close_timeout: 0


      #========================= Filebeat global options ============================

      # Enable filebeat config reloading
      filebeat.config:
        inputs:
          enabled: true
          path: c:/config/filebeat/*.yml
          reload.enabled: true
          reload.period: 10s

      #================================ General ======================================

      # The name of the shipper that publishes the network data. It can be used to group
      # all the transactions sent by a single shipper in the web interface.
      # If this options is not defined, the hostname is used.
      #name:

      # The tags of the shipper are included in their own field with each
      # transaction published. Tags make it easy to group servers by different
      # logical properties.
      #tags: ["service-X", "web-tier"]

      # Optional fields that you can specify to add additional information to the
      # output. Fields can be scalar values, arrays, dictionaries, or any nested
      # combination of these.
      fields:
        environment: "{{ keyOrDefault "config/services/consul/datacenter" "unknown" }}"
        category: "{{ env "RESOURCE_SHORT_NAME" | toLower }}"

      # If this option is set to true, the custom fields are stored as top-level
      # fields in the output document instead of being grouped under a fields
      # sub-dictionary. Default is false.
      #fields_under_root: false


      #================================ Outputs ======================================

      # Configure what output to use when sending the data collected by the beat.

      #------------------------------ MQTT output -----------------------------------
      output.mqtt:
        host: "{{ keyOrDefault "config/services/queue/protocols/mqtt/host" "unknown" }}.service.{{ keyOrDefault "config/services/consul/domain" "unknown" }}"
        port: {{ keyOrDefault "config/services/queue/protocols/mqtt/port" "1883" }}
        topic: "{{ keyOrDefault "config/services/queue/logs/filelog/queue" "unknown" }}"
        {{ with secret "secret/services/queue/users/logs/filelog" }}
          {{ if .Data.password }}
        user: "{{ keyOrDefault "config/services/queue/logs/filelog/vhost" "unknown" }}:{{ .Data.username }}"
        password: "{{ .Data.password }}"
          {{ end }}
        {{ end }}

      #================================ Logging ======================================
      # There are four options for the log output: file, stderr, syslog, eventlog
      # The file output is the default.

      # Sets log level. The default log level is info.
      # Available log levels are: error, warning, info, debug
      #logging.level: info

      # Enable debug output for selected components. To enable all selectors use ["*"]
      # Other available selectors are "beat", "publish", "service"
      # Multiple selectors can be chained.
      #logging.selectors: [ ]

      # Send all logging output to syslog. The default is false.
      #logging.to_syslog: false

      # Send all logging output to Windows Event Logs. The default is false.
      #logging.to_eventlog: false

      # If enabled, filebeat periodically logs its internal metrics that have changed
      # in the last period. For each metric that changed, the delta from the value at
      # the beginning of the period is logged. Also, the total values for
      # all non-zero internal metrics are logged on shutdown. The default is true.
      #logging.metrics.enabled: true

      # The period after which to log the internal metrics. The default is 30s.
      #logging.metrics.period: 30s

      # Logging to rotating files. Set logging.to_files to false to disable logging to
      # files.
      logging.to_files: true
      logging.files:
        # Configure the path where the logs are written. The default is the logs directory
        # under the home path (the binary location).
        #path: /var/log/filebeat

        # The name of the files where the logs are written to.
        #name: filebeat

        # Configure log file size limit. If limit is reached, log file will be
        # automatically rotated
        #rotateeverybytes: 10485760 # = 10MB

        # Number of rotated log files to keep. Oldest files will be deleted first.
        #keepfiles: 7

        # The permissions mask to apply when rotating log files. The default value is 0600.
        # Must be a valid Unix-style file permissions mask expressed in octal notation.
        #permissions: 0600

      # Set to true to log messages in json format.
      #logging.json: false

      #================================ HTTP Endpoint ======================================
      # Each beat can expose internal metrics through a HTTP endpoint. For security
      # reasons the endpoint is disabled by default. This feature is currently experimental.
      # Stats can be access through http://localhost:5066/stats . For pretty JSON output
      # append ?pretty to the URL.

      # Defines if the HTTP endpoint is enabled.
      #http.enabled: false

      # The HTTP endpoint will bind to this hostname or IP address. It is recommended to use only localhost.
      #http.host: localhost

      # Port on which the HTTP endpoint will bind. Default is 5066.
      #http.port: 5066
    CONF
    it 'creates filebeat template file in the consul-template template directory' do
      expect(chef_run).to create_file('c:/config/consul-template/templates/filebeat.ctmpl')
        .with_content(filebeat_config_content)
    end

    consul_template_filebeat_content = <<~CONF
      # This block defines the configuration for a template. Unlike other blocks,
      # this block may be specified multiple times to configure multiple templates.
      # It is also possible to configure templates via the CLI directly.
      template {
        # This is the source file on disk to use as the input template. This is often
        # called the "Consul Template template". This option is required if not using
        # the `contents` option.
        source = "c:/config/consul-template/templates/filebeat.ctmpl"

        # This is the destination path on disk where the source template will render.
        # If the parent directories do not exist, Consul Template will attempt to
        # create them, unless create_dest_dirs is false.
        destination = "#{filebeat_config_path}/filebeat.yml"

        # This options tells Consul Template to create the parent directories of the
        # destination path if they do not exist. The default value is true.
        create_dest_dirs = false

        # This is the optional command to run when the template is rendered. The
        # command will only run if the resulting template changes. The command must
        # return within 30s (configurable), and it must have a successful exit code.
        # Consul Template is not a replacement for a process monitor or init system.
        command = "powershell.exe -noprofile -nologo -noninteractive -command \\"if ((Get-Service -Name filebeat).Status -ne 'Running'){ Start-Service filebeat }\\" "

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
    it 'creates filebeat.hcl in the consul-template template directory' do
      expect(chef_run).to create_file('c:/config/consul-template/config/filebeat.hcl')
        .with_content(consul_template_filebeat_content)
    end
  end
end
