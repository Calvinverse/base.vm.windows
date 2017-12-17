# frozen_string_literal: true

require 'chefspec'
require 'chefspec/berkshelf'

RSpec.configure do |config|
  config.log_level = :debug

  # Specify the operating platform to mock Ohai data from (default: nil)
  config.platform = 'windows'

  # Specify the operating version to mock Ohai data from (default: nil)
  config.version = '2012r2'
end
