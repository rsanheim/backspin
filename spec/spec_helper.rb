require "bundler/setup"
require "backspin"
require "timecop"
require "tmpdir"
require_relative "support/backspin_helper"

RSpec.configure do |config|
  config.filter_run_when_matching :focus
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Reset configuration after each test
  config.after(:each) do
    # Reset configuration to defaults
    Backspin.reset_configuration!
  end

  config.include(BackspinHelper)
end
