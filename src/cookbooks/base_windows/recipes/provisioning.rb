# frozen_string_literal: true

#
# Cookbook Name:: base_windows
# Recipe:: provisioning
#
# Copyright 2017, P. van der Velde
#

#
# CONFIGURE THE PROVISIONING SCRIPT
#

service_name = node['provisioning']['service']['name']
provisioning_bin_path = "#{node['paths']['ops']}/#{service_name}"
directory provisioning_bin_path do
  action :create
  rights :read_execute, 'Everyone', applies_to_children: true, applies_to_self: false
end

provisioning_helper_script = 'Initialize.ps1'
cookbook_file "#{provisioning_bin_path}/#{provisioning_helper_script}" do
  action :create
  source provisioning_helper_script
end

provisioning_script = 'Initialize-Resource.ps1'
cookbook_file "#{provisioning_bin_path}/#{provisioning_script}" do
  action :create
  source provisioning_script
end

#
# WINDOWS SERVICE
#

provisioning_logs_path = "#{node['paths']['logs']}/#{service_name}"
directory provisioning_logs_path do
  action :create
  rights :modify, 'Administrators', applies_to_children: true, applies_to_self: false
end

service_exe_name = node['provisioning']['service']['exe']
remote_file "#{provisioning_bin_path}/#{service_exe_name}.exe" do
  action :create
  source node['winsw']['url']
end

file "#{provisioning_bin_path}/#{service_exe_name}.exe.config" do
  action :create
  content <<~XML
    <configuration>
        <runtime>
            <generatePublisherEvidence enabled="false"/>
        </runtime>
    </configuration>
  XML
end

file "#{provisioning_bin_path}/#{service_exe_name}.xml" do
  content <<~XML
    <?xml version="1.0"?>
    <service>
        <id>#{service_name}</id>
        <name>#{service_name}</name>
        <description>This service executes the environment provisioning for the current resource.</description>

        <executable>powershell.exe</executable>
        <arguments>-NonInteractive -NoProfile -NoLogo -ExecutionPolicy RemoteSigned -File #{provisioning_bin_path}/#{provisioning_script}</arguments>

        <logpath>#{provisioning_logs_path}</logpath>
        <log mode="roll-by-size">
            <sizeThreshold>10240</sizeThreshold>
            <keepFiles>1</keepFiles>
        </log>
        <onfailure action="none"/>
    </service>
  XML
  action :create
end

# Create the event log source for the provisioning service. We'll create it now because the service runs as a normal user
# and is as such not allowed to create eventlog sources
registry_key "HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\services\\eventlog\\Application\\#{service_name}" do
  action :create
  values [{
    data: 'c:\\Windows\\Microsoft.NET\\Framework64\\v4.0.30319\\EventLogMessages.dll',
    name: 'EventMessageFile',
    type: :string
  }]
end

powershell_script 'provisioning_as_service' do
  code <<~POWERSHELL
    $ErrorActionPreference = 'Stop'

    # Using the LocalSystem account so that the scripts that we run have access to everything:
    # https://msdn.microsoft.com/en-us/library/windows/desktop/ms684190%28v=vs.85%29.aspx
    #
    # Provide no credential to run as the LocalSystem account:
    # http://stackoverflow.com/questions/14708825/how-to-create-a-windows-service-in-powershell-for-network-service-account
    $service = Get-Service -Name '#{service_name}' -ErrorAction SilentlyContinue
    if ($service -eq $null)
    {
        New-Service `
            -Name '#{service_name}' `
            -BinaryPathName '#{provisioning_bin_path}/#{service_exe_name}.exe' `
            -DisplayName '#{service_name}' `
            -StartupType Automatic
    }

    # Set the service to restart if it fails
    sc.exe failure #{service_name} reset=86400 actions=restart/5000
  POWERSHELL
end
