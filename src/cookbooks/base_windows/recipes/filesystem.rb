# frozen_string_literal: true

#
# Cookbook Name:: base_windows
# Recipe:: filesystem
#
# Copyright 2017, P. van der Velde
#

config_directory = node['paths']['config']
logs_directory = node['paths']['logs']
ops_directory = node['paths']['ops']

%W[#{config_directory} #{logs_directory} #{ops_directory}].each do |path|
  directory path do
    action :create
    rights :read, 'Everyone', applies_to_children: true
    rights :modify, 'Administrators', applies_to_children: true
  end
end
