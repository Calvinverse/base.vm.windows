# frozen_string_literal: true

#
# Cookbook Name:: base_windows
# Recipe:: system
#
# Copyright 2018, P. van der Velde
#

#
# USER
#

#
# DIRECTORIES
#

# The configuration file for scollector is dropped in the configuration path
# when the resource is provisioned because it contains environment specific information
scollector_config_path = node['scollector']['conf_dir']
scollector_config_file = node['scollector']['config_file']
scollector_config_file_path = "#{scollector_config_path}/#{scollector_config_file}"

directory scollector_config_path do
  action :create
end

#
# INSTALL SCOLLECTOR
#

scollector_install_path = node['scollector']['bin_path']
node.default['scollector']['arch'] = 'amd64'

binary = "scollector-#{node['os']}-#{node['scollector']['arch']}.exe"
remote_file 'scollector' do
  path "#{scollector_install_path}/#{node['scollector']['service']['name']}.exe"
  source "#{node['scollector']['release_url']}/#{node['scollector']['version']}/#{binary}"
  owner 'root'
  mode '0755'
  action :create
end

# Create the service for scollector.
service_name = node['scollector']['service']['name']
powershell_script 'scollector_as_service' do
  code <<~POWERSHELL
    $ErrorActionPreference = 'Stop'

    & #{scollector_install_path} -conf #{scollector_config_file_path} -winsvc install

    # Set the service to restart if it fails
    sc.exe failure #{service_name} reset=86400 actions=restart/5000
    sc.exe config #{service_name} start=delayed-auto
  POWERSHELL
end

service 'scollector' do
  action :enable
end

scollector_template_file = node['scollector']['consul_template_file']
consul_template_template_path = node['consul_template']['template_path']
file "#{consul_template_template_path}/#{scollector_template_file}" do
  action :create
  content <<~CONF
    Host = "http://{{ keyOrDefault "config/services/metrics/host" "unknown" }}.service.{{ keyOrDefault "config/services/consul/domain" "unknown" }}:{{ keyOrDefault "config/services/metrics/port" "80" }}"

    [Tags]
        environment = "{{ keyOrDefault "config/services/consul/datacenter" "unknown" }}"
        os = "windows"
  CONF
  mode '755'
end

# Create the consul-template configuration file
scollector_install_path = node['scollector']['conf_dir']
consul_template_config_path = node['consul_template']['config_path']
file "#{consul_template_config_path}/scollector.hcl" do
  action :create
  content <<~HCL
    # This block defines the configuration for a template. Unlike other blocks,
    # this block may be specified multiple times to configure multiple templates.
    # It is also possible to configure templates via the CLI directly.
    template {
      # This is the source file on disk to use as the input template. This is often
      # called the "Consul Template template". This option is required if not using
      # the `contents` option.
      source = "#{consul_template_template_path}/#{scollector_template_file}"

      # This is the destination path on disk where the source template will render.
      # If the parent directories do not exist, Consul Template will attempt to
      # create them, unless create_dest_dirs is false.
      destination = "#{scollector_config_file_path}"

      # This options tells Consul Template to create the parent directories of the
      # destination path if they do not exist. The default value is true.
      create_dest_dirs = false

      # This is the optional command to run when the template is rendered. The
      # command will only run if the resulting template changes. The command must
      # return within 30s (configurable), and it must have a successful exit code.
      # Consul Template is not a replacement for a process monitor or init system.
      command = "powershell -NoLogo -NonInteractive -NoProfile -Command 'Restart-Service scollector'"

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
