# frozen_string_literal: true

require 'spec_helper'

describe 'base_windows::seven_zip' do
  context 'configures provisioning' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'imports the seven_zip recipe' do
      expect(chef_run).to include_recipe('seven_zip::default')
    end
  end
end
