# frozen_string_literal: true

require "bundler/setup"
require "backspin"
require "timecop"
require "tmpdir"
require_relative "support/backspin_helper"

Backspin.configure do |config|
  config.logger = nil
end

RSpec.configure do |config|
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Reset configuration after each test
  config.after(:each) do
    ENV.delete("BACKSPIN_MODE")
    Backspin.reset_configuration!
  end

  config.include(BackspinHelper)
end
