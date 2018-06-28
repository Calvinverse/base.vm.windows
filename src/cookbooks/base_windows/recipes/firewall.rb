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

firewall_logs_path = "#{node['paths']['logs']['firewall']}"
directory firewall_logs_path do
  action :create
  rights :modify, 'NT SERVICE\MPSSVC', applies_to_children: true, applies_to_self: false
end

powershell_script 'firewall_logging_for_domain_profile' do
  code <<~POWERSHELL
    $ErrorActionPreference = 'Stop'

    Set-NetFirewallProfile `
      -Profile Domain `
      -LogFileName #{firewall_logs_path}/domain.log `
      -LogMaxSizeKilobytes 4096 `
      -LogAllowed true `
      -LogBlocked true `
      -LogIgnored true
  POWERSHELL
end

powershell_script 'firewall_logging_for_private_profile' do
  code <<~POWERSHELL
    $ErrorActionPreference = 'Stop'

    Set-NetFirewallProfile `
      -Profile Private `
      -LogFileName #{firewall_logs_path}/private.log `
      -LogMaxSizeKilobytes 4096 `
      -LogAllowed true `
      -LogBlocked true `
      -LogIgnored true
  POWERSHELL
end

powershell_script 'firewall_logging_for_public_profile' do
  code <<~POWERSHELL
    $ErrorActionPreference = 'Stop'

    Set-NetFirewallProfile `
      -Profile Public `
      -LogFileName #{firewall_logs_path}/public.log `
      -LogMaxSizeKilobytes 4096 `
      -LogAllowed true `
      -LogBlocked true `
      -LogIgnored true
  POWERSHELL
end
