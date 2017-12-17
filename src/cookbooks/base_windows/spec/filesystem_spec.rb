# frozen_string_literal: true

require 'spec_helper'

describe 'base_windows::filesystem' do
  config_path = 'c:/config'
  logs_path = 'c:/logs'
  ops_path = 'c:/ops'

  context 'create the base locations' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'creates the config directory' do
      expect(chef_run).to create_directory(config_path)
    end

    it 'creates the logs directory' do
      expect(chef_run).to create_directory(logs_path)
    end

    it 'creates the ops directory' do
      expect(chef_run).to create_directory(ops_path)
    end
  end
end
