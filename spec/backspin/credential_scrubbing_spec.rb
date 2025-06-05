require "spec_helper"

RSpec.describe "Backspin credential scrubbing" do
  let(:backspin_path) { Pathname.new(File.join("tmp", "backspin")) }

  describe "configuration" do
    it "has credential scrubbing enabled by default" do
      expect(Backspin.configuration.scrub_credentials).to be true
    end

    it "can disable credential scrubbing" do
      Backspin.configure do |config|
        config.scrub_credentials = false
      end

      expect(Backspin.configuration.scrub_credentials).to be false

      # Reset for other tests
      Backspin.reset_configuration!
    end

    it "can add custom credential patterns" do
      Backspin.configure do |config|
        config.add_credential_pattern(/MY_SECRET_[A-Z0-9]+/)
      end

      expect(Backspin.configuration.credential_patterns).to include(/MY_SECRET_[A-Z0-9]+/)

      # Reset for other tests
      Backspin.reset_configuration!
    end
  end

  describe "scrubbing AWS credentials" do
    it "scrubs AWS access key IDs" do
      result = Backspin.call("aws_keys") do
        Open3.capture3("echo AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE")
      end

      record_data = YAML.load_file(result.record_path)
      expect(record_data["commands"].first["stdout"]).to eq("AWS_ACCESS_KEY_ID=********************\n")
    end

    it "scrubs AWS secret keys" do
      result = Backspin.call("aws_secret") do
        Open3.capture3("echo aws_secret_access_key=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
      end

      record_data = YAML.load_file(result.record_path)
      expect(record_data["commands"].first["stdout"]).to eq("#{"*" * 62}\n")
    end
  end

  describe "scrubbing Google credentials" do
    it "scrubs Google API keys" do
      result = Backspin.call("google_api_key") do
        Open3.capture3("echo GOOGLE_API_KEY=AIzaFAKEGmWKa4JsXZ-HjGw7ISLn_3namBGFAKE")
      end

      record_data = YAML.load_file(result.record_path)
      expect(record_data["commands"].first["stdout"]).to eq("GOOGLE_API_KEY=***************************************\n")
    end
  end

  describe "scrubbing generic credentials" do
    it "scrubs API keys" do
      result = Backspin.call("api_key") do
        Open3.capture3("echo api_key=abc123def456ghi789jkl012mno345pqr678")
      end

      record_data = YAML.load_file(result.record_path)
      expect(record_data["commands"].first["stdout"]).to eq("#{"*" * 44}\n")
    end

    it "scrubs passwords" do
      result = Backspin.call("password") do
        Open3.capture3("echo 'database password: supersecretpassword123!'")
      end

      record_data = YAML.load_file(result.record_path)
      expect(record_data["commands"].first["stdout"]).to eq("database #{"*" * 33}\n")
    end
  end

  describe "scrubbing stderr" do
    it "scrubs credentials from stderr as well" do
      result = Backspin.call("stderr_creds") do
        Open3.capture3("sh -c 'echo normal output && echo \"Error: Invalid API_KEY=sk-1234567890abcdef1234567890abcdef\" >&2 && exit 1'")
      end

      record_data = YAML.load_file(result.record_path)
      expect(record_data["commands"].first["stdout"]).to eq("normal output\n")
      expect(record_data["commands"].first["stderr"]).to eq("Error: Invalid #{"*" * 43}\n")
    end
  end

  describe "when scrubbing is disabled" do
    before do
      Backspin.configure do |config|
        config.scrub_credentials = false
      end
    end

    after do
      Backspin.reset_configuration!
    end

    it "does not scrub credentials" do
      result = Backspin.call("no_scrub") do
        Open3.capture3("echo AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE")
      end

      record_data = YAML.load_file(result.record_path)
      expect(record_data["commands"].first["stdout"]).to eq("AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE\n")
    end
  end

  describe "private key detection" do
    it "scrubs private keys" do
      result = Backspin.call("private_key") do
        Open3.capture3("echo '-----BEGIN PRIVATE KEY-----\nMIIEvQIBADANB...'")
      end

      record_data = YAML.load_file(result.record_path)
      expect(record_data["commands"].first["stdout"]).to match(/\*{27}/)
    end
  end

  describe "scrubbing command arguments" do
    it "scrubs AWS credentials in command arguments" do
      result = Backspin.call("args_aws_creds") do
        Open3.capture3("echo", "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE")
      end

      record_data = YAML.load_file(result.record_path)
      args = record_data["commands"].first["args"]

      args_string = args.join(" ")
      expect(args_string).not_to include("AKIAIOSFODNN7EXAMPLE")
      expect(args_string).to include("AWS_ACCESS_KEY_ID=")
      expect(args_string).to match(/\*{20}/)
    end

    it "scrubs API keys in command arguments" do
      result = Backspin.call("args_api_key") do
        Open3.capture3("curl", "-H", "Authorization: Bearer sk-1234567890abcdef", "https://api.example.com")
      end

      record_data = YAML.load_file(result.record_path)
      args = record_data["commands"].first["args"]

      args_string = args.join(" ")
      expect(args_string).not_to include("sk-1234567890abcdef")
      expect(args_string).to include("Authorization:")
      expect(args_string).to match(/\*+/)
    end

    it "scrubs passwords in command arguments" do
      result = Backspin.call("args_password") do
        Open3.capture3("echo", "-psupersecretpassword123", "connecting to database")
      end

      record_data = YAML.load_file(result.record_path)
      args = record_data["commands"].first["args"]

      args_string = args.join(" ")
      expect(args_string).not_to include("supersecretpassword123")
      expect(args_string).to match(/echo \*+ connecting to database/)
    end

    it "handles nested array arguments" do
      result = Backspin.call("args_nested") do
        Open3.capture3("sh", "-c", "export AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY && echo done")
      end

      record_data = YAML.load_file(result.record_path)
      args = record_data["commands"].first["args"]

      args_string = args.join(" ")
      expect(args_string).not_to include("wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY")
      expect(args_string).to match(/sh -c export \*+ && echo done/)
    end

    it "does not scrub arguments when scrubbing is disabled" do
      Backspin.configure do |config|
        config.scrub_credentials = false
      end

      result = Backspin.call("args_no_scrub") do
        Open3.capture3("echo", "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE")
      end

      record_data = YAML.load_file(result.record_path)
      args = record_data["commands"].first["args"]

      args_string = args.join(" ")
      expect(args_string).to include("AKIAIOSFODNN7EXAMPLE")
      expect(args_string).to eq("echo AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE")

      Backspin.reset_configuration!
    end

    it "scrubs credentials from multiple commands" do
      result = Backspin.call("multiple_commands_with_creds") do
        Open3.capture3("echo", "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE")
        Open3.capture3("curl", "-H", "Authorization: Bearer sk-secret123456789", "https://api.example.com")
        Open3.capture3("echo", "password=mysupersecretpassword", "admin", "connection")
      end

      record_data = YAML.load_file(result.record_path)
      commands = record_data["commands"]

      expect(commands.length).to eq(3)

      first_args = commands[0]["args"].join(" ")
      expect(first_args).not_to include("AKIAIOSFODNN7EXAMPLE")
      expect(first_args).to include("AWS_ACCESS_KEY_ID=")

      second_args = commands[1]["args"].join(" ")
      expect(second_args).not_to include("sk-secret123456789")
      expect(second_args).to include("Authorization:")

      third_args = commands[2]["args"].join(" ")
      expect(third_args).not_to include("mysupersecretpassword")
      expect(third_args).to include("echo")
      expect(third_args).to include("admin")
    end
  end
end
