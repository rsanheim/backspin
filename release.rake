# frozen_string_literal: true

require "bundler/gem_tasks"

# Simplified release tasks using gem-release
# Install with: gem install gem-release
# https://github.com/svenfuchs/gem-release
namespace :release do
  desc "Release a new version (bump, tag, release)"
  task :version, [:level] do |t, args|
    level = args[:level] || "patch"

    # Pre-release checks
    # Rake::Task["release:check"].invoke

    puts "\nReleasing #{level} version..."

    # Use gem-release to bump, tag, and release to rubygems and github
    sh "gem bump --version #{level}"
    new_version = File.read("lib/backspin/version.rb").match(/VERSION = "(\d+\.\d+\.\d+)"/)[1]

    sh "bundle install"
    sh "git commit -am 'Bump version to #{new_version}'"
    sh "git push"

    sh "gem release --tag --push"
    Rake::Task["release:github"].invoke(new_version)
  end

  desc "Create GitHub release for specified version or current version"
  task :github, [:version] do |t, args|
    version = args[:version] || Backspin::VERSION

    if system("which gh > /dev/null 2>&1")
      puts "\nCreating GitHub release for v#{version}..."
      sh "gh release create v#{version} --title 'Release v#{version}' --generate-notes"
    else
      puts "\nGitHub CLI not found. Create release manually at:"
      puts "https://github.com/rsanheim/backspin/releases/new?tag=v#{version}"
    end
  end

  desc "Check if ready for release"
  task :check do
    require "open-uri"
    require "json"

    current_version = Backspin::VERSION
    errors = []

    # Check RubyGems for latest version
    begin
      gem_data = JSON.parse(URI.open("https://rubygems.org/api/v1/gems/backspin.json").read)
      latest_version = gem_data["version"]

      if Gem::Version.new(current_version) <= Gem::Version.new(latest_version)
        errors << "Current version (#{current_version}) is not greater than latest released version (#{latest_version})"
      else
        puts "✓ Version #{current_version} is ready for release (latest: #{latest_version})"
      end
    rescue => e
      puts "⚠ Could not check RubyGems version: #{e.message}"
    end

    # Check git status
    if system("git diff --quiet && git diff --cached --quiet")
      puts "✓ No uncommitted changes"
    else
      errors << "You have uncommitted changes"
    end

    # Check branch
    current_branch = `git rev-parse --abbrev-ref HEAD`.strip
    if current_branch != "main"
      puts "⚠ Not on main branch (currently on #{current_branch})"
      print "Continue anyway? (y/N): "
      response = $stdin.gets.chomp
      errors << "Not on main branch" unless response.downcase == "y"
    else
      puts "✓ On main branch"
    end

    unless errors.empty?
      puts "\n❌ Cannot release:"
      errors.each { |e| puts "  - #{e}" }
      abort
    end

    puts "\n✅ All checks passed!"
  end
end

# Convenience tasks
desc "Release patch version"
task "release:patch" => ["release:version"]

desc "Release minor version"
task "release:minor" do
  Rake::Task["release:version"].invoke("minor")
end

desc "Release major version"
task "release:major" do
  Rake::Task["release:version"].invoke("major")
end
