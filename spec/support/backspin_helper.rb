# frozen_string_literal: true

module BackspinHelper
  # Static timestamp to keep record timestamps consistent
  def static_time
    Time.utc(2025, 5, 1, 12, 0, 0, 0)
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
