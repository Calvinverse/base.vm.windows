# frozen_string_literal: true

#
# Cookbook Name:: base_windows
# Recipe:: default
#
# Copyright 2017, P. van der Velde
#

# Always make sure that apt is up to date
apt_update 'update' do
  action :update
end

#
# Include the local recipes
#

include_recipe 'base_windows::filesystem'
include_recipe 'base_windows::firewall'

include_recipe 'base_windows::consul'
include_recipe 'base_windows::network'
include_recipe 'base_windows::provisioning'
