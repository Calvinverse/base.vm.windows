# frozen_string_literal: true

require 'spec_helper'

describe 'base_windows::system_metrics_user' do
  context 'create the user to run the service with' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'creates the telegraf user' do
      expect(chef_run).to run_powershell_script('telegraf_user_with_password_that_does_not_expire')
    end
  end
end
