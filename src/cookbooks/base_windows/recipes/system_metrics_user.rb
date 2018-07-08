# frozen_string_literal: true

#
# Cookbook Name:: base_windows
# Recipe:: system_metrics_user
#
# Copyright 2018, P. van der Velde
#

# Configure the service user under which consul will be run
service_username = node['telegraf']['service']['user_name']
service_password = node['telegraf']['service']['user_password']

# Configure the service user under which consul-template will be run
# Make sure that the user password doesn't expire. The password is a random GUID, so it is unlikely that
# it will ever be guessed. And the user is a normal user who can't do anything so we don't really care about it
powershell_script 'telegraf_user_with_password_that_does_not_expire' do
  code <<~POWERSHELL
    $userName = '#{service_username}'
    $password = ConvertTo-SecureString -String '#{service_password}' -AsPlainText -Force
    $localUser = New-LocalUser `
      -Name $userName `
      -Password $password `
      -PasswordNeverExpires `
      -UserMayNotChangePassword `
      -AccountNeverExpires `
      -Verbose

    Add-LocalGroupMember `
      -Group 'Performance Monitor Users' `
      -Member $localUser.Name `
      -Verbose
  POWERSHELL
end
