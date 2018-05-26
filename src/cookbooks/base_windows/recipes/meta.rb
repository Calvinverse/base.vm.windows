# frozen_string_literal: true

#
# Cookbook Name:: base_windows
# Recipe:: meta
#
# Copyright 2018, P. van der Velde
#

resource_name = node['resource']['name']
env 'BASE_IMAGE' do
  value resource_name
end
