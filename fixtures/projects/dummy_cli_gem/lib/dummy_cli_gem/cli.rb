# frozen_string_literal: true

require "open3"

module DummyCliGem
  module CLI
    module_function

    def run(argv, out: $stdout, err: $stderr)
      command = argv.first

      case command
      when "echo"
        text = argv[1]
        return usage(err) if text.nil? || text.empty?

        stdout, stderr, status = Open3.capture3("echo", text)
      when "list"
        target = argv[1] || "."
        stdout, stderr, status = Open3.capture3("ls", "-1", target)
      else
        return usage(err)
      end

      out.print(stdout)
      err.print(stderr)
      status.exitstatus
    end

    def usage(err)
      err.puts("usage: dummy_cli_gem echo <text> | dummy_cli_gem list <path>")
      1
    end
  end
end
