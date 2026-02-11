# frozen_string_literal: true

require "pathname"

module Backspin
  # Configuration for Backspin
  class Configuration
    attr_accessor :scrub_credentials
    # The directory where backspin will store its files - defaults to fixtures/backspin
    attr_accessor :backspin_dir
    # Whether to raise an exception when verification fails in `run`/`capture` - defaults to true
    attr_accessor :raise_on_verification_failure
    # Regex patterns to scrub from saved output
    attr_reader :credential_patterns

    def initialize
      @scrub_credentials = true
      @raise_on_verification_failure = true
      @credential_patterns = default_credential_patterns
      @backspin_dir = Pathname(Dir.pwd).join("fixtures", "backspin")
    end

    def add_credential_pattern(pattern)
      @credential_patterns << pattern
    end

    def clear_credential_patterns
      @credential_patterns = []
    end

    def reset_credential_patterns
      @credential_patterns = default_credential_patterns
    end

    private

    # Some default patterns for common credential types
    def default_credential_patterns
      [
        # AWS credentials
        /AKIA[0-9A-Z]{16}/, # AWS Access Key ID
        %r{aws_secret_access_key\s*[:=]\s*["']?([A-Za-z0-9/+=]{40})["']?}i,  # AWS Secret Key
        %r{aws_session_token\s*[:=]\s*["']?([A-Za-z0-9/+=]+)["']?}i,         # AWS Session Token

        # Google Cloud credentials
        /AIza[0-9A-Za-z\-_]{35}/, # Google API Key
        /[0-9]+-[0-9A-Za-z_]{32}\.apps\.googleusercontent\.com/, # Google OAuth2 client ID
        /-----BEGIN (RSA )?PRIVATE KEY-----/, # Private keys

        # Generic patterns
        /api[_-]?key\s*[:=]\s*["']?([A-Za-z0-9\-_]{20,})["']?/i, # Generic API keys
        /auth[_-]?token\s*[:=]\s*["']?([A-Za-z0-9\-_]{20,})["']?/i, # Auth tokens
        /Bearer\s+([A-Za-z0-9\-_]+)/,                               # Bearer tokens
        /password\s*[:=]\s*["']?([^"'\s]{8,})["']?/i, # Passwords
        /-p([^"'\s]{8,})/, # MySQL-style password args
        /secret\s*[:=]\s*["']?([A-Za-z0-9\-_]{20,})["']?/i # Generic secrets
      ]
    end
  end
end
