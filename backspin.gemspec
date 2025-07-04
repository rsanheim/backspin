# frozen_string_literal: true

require_relative "lib/backspin/version"

Gem::Specification.new do |spec|
  spec.name = "backspin"
  spec.version = Backspin::VERSION
  spec.authors = ["Rob Sanheim"]
  spec.email = ["rsanheim@gmail.com"]

  spec.summary = "Record and replay CLI interactions for testing"
  spec.description = "Backspin is a Ruby library for characterization testing of command-line interfaces. Inspired by VCR's cassette-based approach, it records and replays CLI interactions to make testing faster and more deterministic."
  spec.homepage = "https://github.com/rsanheim/backspin"
  spec.license = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 3.1.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(test|spec|features)/}) }
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "ostruct"
  spec.add_dependency "rspec-mocks", "~> 3"
end
