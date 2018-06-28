# frozen_string_literal: true

require 'spec_helper'

describe 'base_windows::firewall' do
  context 'configures the firewall' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'installs the default firewall' do
      expect(chef_run).to install_firewall('default')
    end

    it 'opens the WinRM TCP port' do
      expect(chef_run).to create_firewall_rule('winrm').with(
        command: :allow,
        dest_port: 5985,
        direction: :in,
        protocol: :tcp
      )
    end
  end

  firewall_logs_path = 'c:/logs/firewall'
  context 'create the log locations' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'creates the firewall logs directory' do
      expect(chef_run).to create_directory(firewall_logs_path)
    end

    it 'sets the domain profile logs' do
      expect(chef_run).to run_powershell_script('firewall_logging_for_domain_profile')
    end

    it 'sets the private profile logs' do
      expect(chef_run).to run_powershell_script('firewall_logging_for_private_profile')
    end

    it 'sets the public profile logs' do
      expect(chef_run).to run_powershell_script('firewall_logging_for_public_profile')
    end
  end
end
