# frozen_string_literal: true

require "bundler/setup"
require "pathname"
require "yaml"
require "backspin"
require "dummy_cli_gem"

BACKSPIN_DIR = Pathname(__dir__).join("fixtures", "backspin")

Backspin.configure do |config|
  config.backspin_dir = BACKSPIN_DIR
  config.logger = nil
end

RSpec.configure do |config|
  config.disable_monkey_patching!

  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end
end
