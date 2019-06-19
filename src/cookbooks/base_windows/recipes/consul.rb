# frozen_string_literal: true

#
# Cookbook Name:: base_windows
# Recipe:: consul
#
# Copyright 2017, P. van der Velde
#

# Configure the service user under which consul will be run
service_username = node['consul']['service']['user_name']
service_password = node['consul']['service']['user_password']

# Configure the service user under which consul will be run
# Make sure that the user password doesn't expire. The password is a random GUID, so it is unlikely that
# it will ever be guessed. And the user is a normal user who can't do anything so we don't really care about it
powershell_script 'consul_user_with_password_that_does_not_expire' do
  code <<~POWERSHELL
    $user = '#{service_username}'
    $password = '#{service_password}'
    $ObjOU = [ADSI]"WinNT://$env:ComputerName"
    $objUser = $objOU.Create("User", $user)
    $objUser.setpassword($password)
    $objUser.UserFlags = 64 + 65536 # ADS_UF_PASSWD_CANT_CHANGE + ADS_UF_DONT_EXPIRE_PASSWD
    $objUser.SetInfo()
  POWERSHELL
end

# Grant the user the LogOnAsService permission. Following this anwer on SO: http://stackoverflow.com/a/21235462/539846
# With some additional bug fixes to get the correct line from the export file and to put the correct text in the import file
powershell_script 'consul_user_grant_service_logon_rights' do
  code <<~POWERSHELL
    $ErrorActionPreference = 'Stop'

    $userName = '#{service_username}'

    $tempPath = "c:\\temp"
    if (-not (Test-Path $tempPath))
    {
        New-Item -Path $tempPath -ItemType Directory | Out-Null
    }

    $import = Join-Path -Path $tempPath -ChildPath "import.inf"
    if(Test-Path $import)
    {
        Remove-Item -Path $import -Force
    }

    $export = Join-Path -Path $tempPath -ChildPath "export.inf"
    if(Test-Path $export)
    {
        Remove-Item -Path $export -Force
    }

    $secedt = Join-Path -Path $tempPath -ChildPath "secedt.sdb"
    if(Test-Path $secedt)
    {
        Remove-Item -Path $secedt -Force
    }

    $sid = ((New-Object System.Security.Principal.NTAccount($userName)).Translate([System.Security.Principal.SecurityIdentifier])).Value

    secedit /export /cfg $export
    $line = (Select-String $export -Pattern "SeServiceLogonRight").Line
    $sids = $line.Substring($line.IndexOf('=') + 1).Trim()

    if (-not ($sids.Contains($sid)))
    {
        Write-Host ("Granting SeServiceLogonRight to user account: {0} on host: {1}." -f $userName, $computerName)
        $lines = @(
                "[Unicode]",
                "Unicode=yes",
                "[System Access]",
                "[Event Audit]",
                "[Registry Values]",
                "[Version]",
                "signature=`"`$CHICAGO$`"",
                "Revision=1",
                "[Profile Description]",
                "Description=GrantLogOnAsAService security template",
                "[Privilege Rights]",
                "SeServiceLogonRight = $sids,*$sid"
            )
        foreach ($line in $lines)
        {
            Add-Content $import $line
        }

        secedit /import /db $secedt /cfg $import
        secedit /configure /db $secedt
        gpupdate /force
    }
    else
    {
        Write-Host ("User account: {0} on host: {1} already has SeServiceLogonRight." -f $userName, $computerName)
    }
  POWERSHELL
end

#
# INSTALL CONSUL
#

service_name = node['consul']['service']['name']
consul_bin_path = node['consul']['path']['bin']
directory consul_bin_path do
  action :create
  inherits false
  rights :read_execute, service_username, applies_to_children: true, applies_to_self: true
  rights :full_control, 'Administrators', applies_to_children: true
end

consul_data_path = "#{consul_bin_path}/data"
directory consul_data_path do
  action :create
  rights :full_control, service_username, applies_to_children: true, applies_to_self: true
end

consul_config_path = "#{node['paths']['config']}/#{service_name}"
directory consul_config_path do
  action :create
  inherits false
  rights :read_execute, service_username, applies_to_children: true, applies_to_self: true
  rights :full_control, 'Administrators', applies_to_children: true
end

consul_zip_path = "#{node['paths']['temp']}/consul.zip"
remote_file consul_zip_path do
  action :create
  source node['consul']['url']
end

consul_exe_path = node['consul']['path']['exe']
seven_zip_archive consul_bin_path do
  overwrite true
  source consul_zip_path
  timeout 30
end

# We need to multiple-escape the escape character because of ruby string and regex etc. etc. See here: http://stackoverflow.com/a/6209532/539846
consul_config_file = 'consul_base.json'
file "#{consul_bin_path}/#{consul_config_file}" do
  content <<~JSON
    {
      "addresses": {
        "http": "0.0.0.0"
      },
      "client_addr": "127.0.0.1",

      "data_dir": "#{consul_data_path}",

      "disable_host_node_id": true,
      "disable_remote_exec": true,
      "disable_update_check": true,

      "dns_config": {
        "allow_stale": true,
        "max_stale": "87600h",
        "node_ttl": "30s",
        "service_ttl": {
          "*": "30s"
        }
      },

      "log_level" : "INFO",

      "ports": {
        "dns": 8600,
        "http": 8500,
        "serf_lan": 8301,
        "serf_wan": 8302,
        "server": 8300
      },

      "server": false,

      "skip_leave_on_interrupt" : true,

      "verify_incoming" : false,
      "verify_outgoing": false
    }
  JSON
end

#
# CONFIGURATION
#

telegraf_statsd_port = node['telegraf']['statsd']['port']
file "#{consul_config_path}/metrics.json" do
  action :create
  content <<~JSON
    {
      "telemetry": {
        "disable_hostname": true,
        "statsd_address": "127.0.0.1:#{telegraf_statsd_port}"
      }
    }
  JSON
end

#
# WINDOWS SERVICE
#

consul_logs_path = "#{node['paths']['logs']}/#{service_name}"
directory consul_logs_path do
  action :create
  rights :modify, service_username, applies_to_children: true, applies_to_self: false
end

service_exe_name = node['consul']['service']['exe']
remote_file "#{consul_bin_path}/#{service_exe_name}.exe" do
  action :create
  source node['winsw']['url']
end

file "#{consul_bin_path}/#{service_exe_name}.exe.config" do
  action :create
  content <<~XML
    <configuration>
        <runtime>
            <generatePublisherEvidence enabled="false"/>
        </runtime>
    </configuration>
  XML
end

file "#{consul_bin_path}/#{service_exe_name}.xml" do
  content <<~XML
    <?xml version="1.0"?>
    <service>
        <id>#{service_name}</id>
        <name>#{service_name}</name>
        <description>This service runs the consul agent.</description>

        <executable>#{consul_exe_path}</executable>
        <argument>agent</argument>
        <argument>-config-file=#{consul_bin_path}/#{consul_config_file}</argument>
        <argument>-config-dir=#{consul_config_path}</argument>
        <priority>high</priority>

        <logpath>#{consul_logs_path}</logpath>
        <log mode="roll-by-size">
            <sizeThreshold>10240</sizeThreshold>
            <keepFiles>1</keepFiles>
        </log>
        <onfailure action="restart"/>
    </service>
  XML
  action :create
end

powershell_script 'consul_as_service' do
  code <<-POWERSHELL
    $ErrorActionPreference = 'Stop'

    $securePassword = ConvertTo-SecureString "#{service_password}" -AsPlainText -Force

    # Note the .\\ is to get the local machine account as per here:
    # http://stackoverflow.com/questions/313622/powershell-script-to-change-service-account#comment14535084_315616
    $credential = New-Object pscredential((".\\" + "#{service_username}"), $securePassword)

    $service = Get-Service -Name '#{service_name}' -ErrorAction SilentlyContinue
    if ($service -eq $null)
    {
        New-Service `
            -Name '#{service_name}' `
            -BinaryPathName '#{consul_bin_path}/#{service_exe_name}.exe' `
            -Credential $credential `
            -DisplayName '#{service_name}' `
            -StartupType Disabled
    }

    # Set the service to restart if it fails
    sc.exe failure #{service_name} reset=86400 actions=restart/5000
  POWERSHELL
end

# Create the event log source for the jenkins service. We'll create it now because the service runs as a normal user
# and is as such not allowed to create eventlog sources
registry_key "HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\services\\eventlog\\Application\\#{service_name}" do
  values [{
    name: 'EventMessageFile',
    type: :string,
    data: 'c:\\Windows\\Microsoft.NET\\Framework64\\v4.0.30319\\EventLogMessages.dll'
  }]
  action :create
end

#
# ALLOW CONSUL THROUGH THE FIREWALL
#

firewall_rule 'consul-http' do
  command :allow
  description 'Allow Consul HTTP traffic'
  dest_port 8500
  direction :in
end

firewall_rule 'consul-dns' do
  command :allow
  description 'Allow Consul DNS traffic'
  dest_port 8600
  direction :in
  protocol :udp
end

firewall_rule 'consul-rpc' do
  command :allow
  description 'Allow Consul rpc LAN traffic'
  dest_port 8300
  direction :in
end

firewall_rule 'consul-serf-lan-tcp' do
  command :allow
  description 'Allow Consul serf LAN traffic on the TCP port'
  dest_port 8301
  direction :in
  protocol :tcp
end

firewall_rule 'consul-serf-lan-udp' do
  command :allow
  description 'Allow Consul serf LAN traffic on the UDP port'
  dest_port 8301
  direction :in
  protocol :udp
end

firewall_rule 'consul-serf-wan-tcp' do
  command :allow
  description 'Allow Consul serf WAN traffic on the TCP port'
  dest_port 8302
  direction :in
  protocol :tcp
end

firewall_rule 'consul-serf-wan-udp' do
  command :allow
  description 'Allow Consul serf WAN traffic on the UDP port'
  dest_port 8302
  direction :in
  protocol :udp
end
