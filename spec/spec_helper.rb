require "bundler/setup"
require "backspin"
require "timecop"
require "tmpdir"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"
  config.filter_run_when_matching :focus

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Reset configuration after each test
  config.after(:each) do
    # Reset configuration to defaults
    Backspin.reset_configuration!
  end

  module BackspinHelper
    def static_time
      Time.parse("2025-05-01T12:00:00Z")
    end

    # Setup Backspin to use a temporary directory, and reset config after the block
    def with_tmp_dir_for_backspin(&block)
      Dir.mktmpdir("backspin_data") do |dir|
        path = Pathname.new(dir)  
        Backspin.configure do |config|
          config.backspin_dir = path
        end

        block.call
      ensure
        Backspin.reset_configuration!
      end
    end
  end

  config.include(BackspinHelper)
end