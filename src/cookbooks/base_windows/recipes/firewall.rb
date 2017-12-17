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
