# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "standard/rake"

RSpec::Core::RakeTask.new(:spec)

def run_in_fake_gem(command)
  dummy_app_dir = File.expand_path("fixtures/projects/dummy_cli_gem", __dir__)

  Bundler.with_unbundled_env do
    Dir.chdir(dummy_app_dir) do
      sh "bundle check || bundle install"
      sh command
    end
  end
end

namespace :spec do
  desc "Run the dummy fixture gem specs with Backspin (decoupled from main suite)"
  task :fake_gem do
    run_in_fake_gem("bundle exec rspec")
  end

  desc "Re-record Backspin YAML fixtures for the dummy fixture gem"
  task :fake_gem_record do
    original_record_mode = ENV["RECORD_MODE"]
    ENV["RECORD_MODE"] = "record"
    run_in_fake_gem("bundle exec rspec")
  ensure
    ENV["RECORD_MODE"] = original_record_mode
  end
end

task default: %i[spec standard]

load "release.rake" if File.exist?("release.rake")
