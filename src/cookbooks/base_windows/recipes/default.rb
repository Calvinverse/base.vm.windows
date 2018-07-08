# frozen_string_literal: true

#
# Cookbook Name:: base_windows
# Recipe:: default
#
# Copyright 2017, P. van der Velde
#

#
# Include the local recipes
#

# Need to define the metrics user first so that other recipes can grant that user access to logs
include_recipe 'base_windows::system_metrics_user'

include_recipe 'base_windows::filesystem'
include_recipe 'base_windows::firewall'

include_recipe 'base_windows::meta'

include_recipe 'base_windows::seven_zip'

include_recipe 'base_windows::consul'
include_recipe 'base_windows::consul_template'

include_recipe 'base_windows::system'
include_recipe 'base_windows::system_metrics'
include_recipe 'base_windows::system_logs'

include_recipe 'base_windows::network'
include_recipe 'base_windows::provisioning'
