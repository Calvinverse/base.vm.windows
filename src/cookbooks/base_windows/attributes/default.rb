# frozen_string_literal: true

# Variables

config_path = 'c:/config'
logs_path = 'c:/logs'
ops_path = 'c:/ops'
temp_path = 'c:/temp'

#
# CONSUL
#

default['consul']['service']['exe'] = 'consul_service'
default['consul']['service']['name'] = 'consul'
default['consul']['service']['user_name'] = 'consul'
default['consul']['service']['user_password'] = SecureRandom.uuid

#
# CONSULTEMPLATE
#

default['consul_template']['service']['exe'] = 'consul-template_service'
default['consul_template']['service']['name'] = 'consul-template'
default['consul_template']['service']['user_name'] = 'consul-template'
default['consul_template']['service']['user_password'] = SecureRandom.uuid

default['consul_template']['config_path'] = "#{config_path}/#{node['consul_template']['service']['name']}/config"
default['consul_template']['template_path'] = "#{config_path}/#{node['consul_template']['service']['name']}/templates"

#
# FILESYSTEM
#

default['paths']['config'] = config_path
default['paths']['logs'] = logs_path
default['paths']['ops'] = ops_path
default['paths']['temp'] = temp_path

#
# FIREWALL
#

# Allow communication via WinRM
default['firewall']['allow_winrm'] = true

# Allow communication on the loopback address (127.0.0.1 and ::1)
default['firewall']['allow_loopback'] = true

# Do not allow MOSH connections
default['firewall']['allow_mosh'] = false

# do not allow SSH
default['firewall']['allow_ssh'] = false

# No communication via IPv6 at all
default['firewall']['ipv6_enabled'] = false

#
# PROVISIONING
#

default['provisioning']['service']['exe'] = 'provisioning_service'
default['provisioning']['service']['name'] = 'provisioning'

#
# SCOLLECTOR
#

default['scollector']['service']['exe'] = 'scollector'
default['scollector']['service']['name'] = 'scollector'

default['scollector']['release_url'] = 'https://github.com/bosun-monitor/bosun/releases/download'
default['scollector']['bin_path'] = "#{ops_path}/#{node['scollector']['service']['name']}"
default['scollector']['conf_dir'] = "#{config_path}/#{node['scollector']['service']['name']}"
default['scollector']['version'] = '0.6.0-beta1'

default['scollector']['config_file'] = 'scollector.toml'
default['scollector']['consul_template_file'] = 'scollector.ctmpl'

#
# UNBOUND
#

default['unbound']['service']['exe'] = 'unbound_service'
default['unbound']['service']['name'] = 'unbound'
default['unbound']['service']['user_name'] = 'unbound_user'
default['unbound']['service']['user_password'] = SecureRandom.uuid

#
# WINSW
#

default['winsw']['version'] = '2.1.2'
default['winsw']['url'] = "https://github.com/kohsuke/winsw/releases/download/winsw-v#{node['winsw']['version']}/WinSW.NET4.exe"

default['winsw']['path']['bin'] = "#{ops_path}/winsw"
