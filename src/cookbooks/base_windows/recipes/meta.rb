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

resource_version_major = node['resource']['version_major']
env 'RESOURCE_VERSION_MAJOR' do
  value resource_version_major
end

resource_version_minor = node['resource']['version_minor']
env 'RESOURCE_VERSION_MINOR' do
  value resource_version_minor
end

resource_version_patch = node['resource']['version_patch']
env 'RESOURCE_VERSION_PATCH' do
  value resource_version_patch
end

resource_version_semantic = node['resource']['version_semantic']
env 'RESOURCE_VERSION_SEMANTIC' do
  value resource_version_semantic
end

env 'STATSD_ENABLED_SERVICES' do
  value 'consul'
end
