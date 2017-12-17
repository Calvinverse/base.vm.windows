# frozen_string_literal: true

# Variables

config_path = 'c:/config'
logs_path = 'c:/logs'
ops_path = 'c:/ops'

#
# CONSUL
#

default['consul']['service']['exe'] = 'consul_service'
default['consul']['service']['name'] = 'consul'
default['consul']['service']['user_name'] = 'consul'
default['consul']['service']['user_password'] = SecureRandom.uuid

#
# FILESYSTEM
#

default['paths']['config'] = config_path
default['paths']['logs'] = logs_path
default['paths']['ops'] = ops_path

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
# UNBOUND
#

default['unbound']['service']['exe'] = 'unbound_service'
default['unbound']['service']['name'] = 'unbound'
default['unbound']['service']['user_name'] = 'unbound_user'
default['unbound']['service']['user_password'] = SecureRandom.uuid
