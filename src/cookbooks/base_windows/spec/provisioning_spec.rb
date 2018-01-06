# frozen_string_literal: true

require 'spec_helper'

describe 'base_windows::provisioning' do
  provisioning_logs_path = 'c:/logs/provisioning'
  provisioning_bin_path = 'c:/ops/provisioning'

  service_name = 'provisioning'
  provisioning_script = 'Initialize-Resource.ps1'
  provisioning_helper_script = 'Initialize.ps1'

  context 'create the log locations' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'creates the provisioning logs directory' do
      expect(chef_run).to create_directory(provisioning_logs_path)
    end
  end

  context 'create the provisioning locations' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'creates the provisioning bin directory' do
      expect(chef_run).to create_directory(provisioning_bin_path)
    end

    it 'creates Initialize.ps1 in the provisioning ops directory' do
      expect(chef_run).to create_cookbook_file("#{provisioning_bin_path}/#{provisioning_helper_script}").with_source(provisioning_helper_script)
    end

    it 'creates Initialize-Resource.ps1 in the provisioning ops directory' do
      expect(chef_run).to create_cookbook_file("#{provisioning_bin_path}/#{provisioning_script}").with_source(provisioning_script)
    end
  end

  context 'install provisioning as service' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    win_service_name = 'provisioning_service'
    it 'creates provisioning_service.exe in the provisioning bin directory' do
      expect(chef_run).to create_cookbook_file("#{provisioning_bin_path}/#{win_service_name}.exe").with_source('WinSW.NET4.exe')
    end

    provisioning_service_exe_config_content = <<~XML
      <configuration>
          <runtime>
              <generatePublisherEvidence enabled="false"/>
          </runtime>
      </configuration>
    XML
    it 'creates provisioning_service.exe.config in the provisioning ops directory' do
      expect(chef_run).to create_file("#{provisioning_bin_path}/#{win_service_name}.exe.config").with_content(provisioning_service_exe_config_content)
    end

    provisioning_service_xml_content = <<~XML
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
              <keepFiles>8</keepFiles>
          </log>
          <onfailure action="none"/>
      </service>
    XML
    it 'creates provisioning_service.xml in the provisioning ops directory' do
      expect(chef_run).to create_file("#{provisioning_bin_path}/#{win_service_name}.xml").with_content(provisioning_service_xml_content)
    end

    it 'installs provisioning as service' do
      expect(chef_run).to run_powershell_script('provisioning_as_service')
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
end
