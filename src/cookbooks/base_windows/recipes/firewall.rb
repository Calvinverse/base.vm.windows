# frozen_string_literal: true

#
# Cookbook Name:: base_windows
# Recipe:: firewall
#
# Copyright 2017, P. van der Velde
#

firewall 'default' do
  action :install
end

firewall_rule 'winrm' do
  command :allow
  description 'Allow WinRM traffic'
  dest_port 5985
  direction :in
end

telegraf_service_username = node['telegraf']['service']['user_name']

firewall_logs_path = node['firewall']['paths']['logs']
directory firewall_logs_path do
  action :create
  rights :modify, 'NT SERVICE\MPSSVC', applies_to_children: true, applies_to_self: false
  rights :read, telegraf_service_username, applies_to_children: true, applies_to_self: true
end

# Normally powershell doesn't care about '/' vs '\' but apparently the windows firewall does care
# so the log path needs to be a proper windows path, sigh
powershell_script 'firewall_logging' do
  code <<~POWERSHELL
    $ErrorActionPreference = 'Stop'

    Set-NetFirewallProfile `
      -Name Domain `
      -AllowInboundRules True `
      -DefaultInboundAction Block `
      -DefaultOutboundAction Allow `
      -LogFileName #{firewall_logs_path.gsub('/', '\\\\')}\\domain.log `
      -LogMaxSizeKilobytes 4096 `
      -LogAllowed True `
      -LogBlocked True `
      -LogIgnored True

    Set-NetFirewallProfile `
      -Name Private `
      -AllowInboundRules True `
      -DefaultInboundAction Block `
      -DefaultOutboundAction Allow `
      -LogFileName #{firewall_logs_path.gsub('/', '\\\\')}\\private.log `
      -LogMaxSizeKilobytes 4096 `
      -LogAllowed True `
      -LogBlocked True `
      -LogIgnored True

    Set-NetFirewallProfile `
      -Name Public `
      -AllowInboundRules True `
      -DefaultInboundAction Block `
      -DefaultOutboundAction Allow `
      -LogFileName #{firewall_logs_path.gsub('/', '\\\\')}\\public.log `
      -LogMaxSizeKilobytes 4096 `
      -LogAllowed True `
      -LogBlocked True `
      -LogIgnored True
  POWERSHELL
end
