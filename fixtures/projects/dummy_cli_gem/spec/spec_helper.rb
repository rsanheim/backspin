# frozen_string_literal: true

require "bundler/setup"
require "pathname"
require "yaml"
require "backspin"
require "dummy_cli_gem"

RSpec.configure do |config|
  config.disable_monkey_patching!

  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end
end
