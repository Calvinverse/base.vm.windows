# frozen_string_literal: true

require 'spec_helper'

describe 'base_windows::consul' do
  consul_config_path = 'c:/config/consul'
  consul_logs_path = 'c:/logs/consul'
  consul_bin_path = 'c:/ops/consul'

  service_name = 'consul'
  consul_config_file = 'consul_base.json'

  context 'create the user to run the service with' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'creates the consul user' do
      expect(chef_run).to run_powershell_script('consul_user_with_password_that_does_not_expire')
    end
  end

  context 'create the consul locations' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'creates the consul base directory' do
      expect(chef_run).to create_directory(consul_bin_path)
    end

    it 'creates consul.exe in the consul ops directory' do
      expect(chef_run).to extract_seven_zip_archive("#{consul_bin_path}/#{service_name}.exe")
    end

    consul_default_config_content = <<~JSON
      {
        "addresses": {
          "http": "0.0.0.0"
        },
        "client_addr": "127.0.0.1",

        "data_dir": "c:/ops/consul/data",

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

        "leave_on_terminate" : false,

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
    it 'creates consul_default.json in the consul ops directory' do
      expect(chef_run).to create_file("#{consul_bin_path}/#{consul_config_file}").with_content(consul_default_config_content)
    end
  end

  context 'create the log locations' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'creates the consul logs directory' do
      expect(chef_run).to create_directory(consul_logs_path)
    end
  end

  context 'install consul as service' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    win_service_name = 'consul_service'
    it 'creates consul_service.exe in the consul ops directory' do
      expect(chef_run).to extract_seven_zip_archive("#{consul_bin_path}/#{win_service_name}.exe")
    end

    service_exe_config_content = <<~XML
      <configuration>
          <runtime>
              <generatePublisherEvidence enabled="false"/>
          </runtime>
      </configuration>
    XML
    it 'creates consul_service.exe.config in the consul ops directory' do
      expect(chef_run).to create_file("#{consul_bin_path}/#{win_service_name}.exe.config").with_content(service_exe_config_content)
    end

    consul_service_xml_content = <<~XML
      <?xml version="1.0"?>
      <service>
          <id>#{service_name}</id>
          <name>#{service_name}</name>
          <description>This service runs the consul agent.</description>

          <executable>#{consul_bin_path}/consul.exe</executable>
          <arguments>agent -config-file=#{consul_bin_path}/#{consul_config_file} -config-dir=#{consul_config_path}</arguments>
          <priority>high</priority>

          <logpath>#{consul_logs_path}</logpath>
          <log mode="roll-by-size">
              <sizeThreshold>10240</sizeThreshold>
              <keepFiles>8</keepFiles>
          </log>
          <onfailure action="restart"/>
      </service>
    XML
    it 'creates consul_service.xml in the consul ops directory' do
      expect(chef_run).to create_file("#{consul_bin_path}/#{win_service_name}.xml").with_content(consul_service_xml_content)
    end

    it 'installs consul as service' do
      expect(chef_run).to run_powershell_script('consul_as_service')
    end

    it 'creates the windows service event log' do
      expect(chef_run).to create_registry_key("HKEY_LOCAL_MACHINE\\SYSTEM\\CurrentControlSet\\services\\eventlog\\Application\\#{service_name}").with(
        values: [{
          name: 'EventMessageFile',
          type: :string,
          data: 'c:\\Windows\\Microsoft.NET\\Framework64\\v4.0.30319\\EventLogMessages.dll'
        }]
      )
    end
  end

  context 'create the config locations' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'creates the consul config directory' do
      expect(chef_run).to create_directory(consul_config_path)
    end

    consul_metrics_config_content = <<~JSON
      {
        "telemetry": {
          "disable_hostname": true,
          "statsd_address": "127.0.0.1:8125"
        }
      }
    JSON
    it 'creates metrics.json in the consul config directory' do
      expect(chef_run).to create_file("#{consul_config_path}/metrics.json").with_content(consul_metrics_config_content)
    end
  end

  context 'configures the firewall for consul' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'opens the Consul HTTP port' do
      expect(chef_run).to create_firewall_rule('consul-http').with(
        command: :allow,
        dest_port: 8500,
        direction: :in
      )
    end

    it 'opens the Consul DNS port' do
      expect(chef_run).to create_firewall_rule('consul-dns').with(
        command: :allow,
        dest_port: 8600,
        direction: :in,
        protocol: :udp
      )
    end

    it 'opens the Consul rpc port' do
      expect(chef_run).to create_firewall_rule('consul-rpc').with(
        command: :allow,
        dest_port: 8300,
        direction: :in
      )
    end

    it 'opens the Consul serf LAN TCP port' do
      expect(chef_run).to create_firewall_rule('consul-serf-lan-tcp').with(
        command: :allow,
        dest_port: 8301,
        direction: :in,
        protocol: :tcp
      )
    end

    it 'opens the Consul serf LAN UDP port' do
      expect(chef_run).to create_firewall_rule('consul-serf-lan-udp').with(
        command: :allow,
        dest_port: 8301,
        direction: :in,
        protocol: :udp
      )
    end

    it 'opens the Consul serf WAN TCP port' do
      expect(chef_run).to create_firewall_rule('consul-serf-wan-tcp').with(
        command: :allow,
        dest_port: 8302,
        direction: :in,
        protocol: :tcp
      )
    end

    it 'opens the Consul serf WAN UDP port' do
      expect(chef_run).to create_firewall_rule('consul-serf-wan-udp').with(
        command: :allow,
        dest_port: 8302,
        direction: :in,
        protocol: :udp
      )
    end
  end
end
