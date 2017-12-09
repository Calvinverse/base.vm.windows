# frozen_string_literal: true

#
# Cookbook Name:: base_windows
# Recipe:: filesystem
#
# Copyright 2017, P. van der Velde
#

config_directory = node['paths']['config']
directory config_directory do
  rights :read, 'Everyone', applies_to_children: true
  rights :modify, 'Administrators', applies_to_children: true
  action :create
end

log_directory = node['paths']['log']
directory log_directory do
  rights :read, 'Everyone', applies_to_children: true
  rights :modify, 'Administrators', applies_to_children: true
  action :create
end

ops_directory = node['paths']['ops']
directory ops_directory do
  rights :read, 'Everyone', applies_to_children: true
  rights :modify, 'Administrators', applies_to_children: true
  action :create
end
