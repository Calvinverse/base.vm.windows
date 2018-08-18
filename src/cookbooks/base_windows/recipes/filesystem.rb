# frozen_string_literal: true

#
# Cookbook Name:: base_windows
# Recipe:: filesystem
#
# Copyright 2017, P. van der Velde
#

config_directory = node['paths']['config']
ops_directory = node['paths']['ops']

# We don't necessarily want to grant read access to the child directories of
# the ops and config directories because the config files in these directories may
# contain sensitive information (e.g. the consul encrypt key)
%W[#{config_directory} #{ops_directory}].each do |path|
  directory path do
    action :create
    inherits false
    rights :read, 'Everyone', applies_to_children: false
    rights :full_control, 'Administrators', applies_to_children: true
  end
end

logs_directory = node['paths']['logs']
temp_directory = node['paths']['temp']

%W[#{logs_directory} #{temp_directory}].each do |path|
  directory path do
    action :create
    rights :read, 'Everyone', applies_to_children: true
    rights :full_control, 'Administrators', applies_to_children: true
  end
end
