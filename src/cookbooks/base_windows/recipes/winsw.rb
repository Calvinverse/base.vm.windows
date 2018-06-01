# frozen_string_literal: true

#
# Cookbook Name:: base_windows
# Recipe:: winsw
#
# Copyright 2018, P. van der Velde
#

winsw_zip_path = "#{node['paths']['temp']}/winsw.zip"
remote_file winsw_zip_path do
  action :create
  source node['winsw']['url']
end
