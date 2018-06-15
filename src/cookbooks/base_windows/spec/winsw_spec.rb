# frozen_string_literal: true

require 'spec_helper'

describe 'base_windows::winsw' do
  context 'installs the binaries' do
    let(:chef_run) { ChefSpec::SoloRunner.converge(described_recipe) }

    it 'downloads the winsw zip file' do
      expect(chef_run).to create_remote_file('c:/temp/winsw.zip')
    end
  end
end
