#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "pathname"
require "backspin"

project_root = Pathname(__dir__).join("..").expand_path
record_dir = project_root.join("spec", "fixtures", "backspin")

Backspin.configure do |config|
  config.backspin_dir = record_dir
  config.logger = nil
end

Dir.chdir(project_root) do
  Backspin.run(
    ["ruby", "exe/dummy_cli_gem", "echo", "hello from dummy gem"],
    name: "dummy_echo",
    mode: :record
  )

  Backspin.run(
    ["ruby", "exe/dummy_cli_gem", "list", "spec/fixtures/listing_target"],
    name: "dummy_ls",
    mode: :record
  )
end

puts "Recorded dummy_cli_gem fixtures in #{record_dir}"
