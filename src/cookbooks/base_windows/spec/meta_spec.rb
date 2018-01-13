# frozen_string_literal: true

require 'spec_helper'

describe 'base_windows::meta' do
  context 'updates the environment variables' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'sets the BASE_IMAGE environment variable' do
      expect(chef_run).to create_env('BASE_IMAGE')
    end
  end
end
