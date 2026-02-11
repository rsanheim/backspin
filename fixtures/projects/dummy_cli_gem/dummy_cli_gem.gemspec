# frozen_string_literal: true

require_relative "lib/dummy_cli_gem/version"

Gem::Specification.new do |spec|
  spec.name = "dummy_cli_gem"
  spec.version = DummyCliGem::VERSION
  spec.authors = ["Backspin"]
  spec.email = ["noreply@example.com"]
  spec.summary = "Dummy CLI gem fixture for Backspin full-stack verification"
  spec.description = "Fixture gem that shells out to unix utilities and is tested via Backspin snapshots."
  spec.homepage = "https://example.com/dummy_cli_gem"
  spec.license = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 3.1.0")

  spec.files = Dir.chdir(__dir__) do
    Dir["lib/**/*.rb", "exe/*", "spec/**/*", "script/**/*", "README.md", "LICENSE.txt"]
  end
  spec.bindir = "exe"
  spec.executables = ["dummy_cli_gem"]
  spec.require_paths = ["lib"]
end
