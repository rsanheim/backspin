module Backspin
  class RecordFormatError < StandardError; end

  class NoMoreRecordingsError < StandardError; end

  class Record
    FORMAT_VERSION = "2.0"
    attr_reader :path, :commands, :first_recorded_at

    def self.load_or_create(path)
      record = new(path)
      record.load_from_file if File.exist?(path)
      record
    end

    def self.load_from_file(path)
      raise Backspin::RecordNotFoundError unless File.exist?(path)
      record = new(path)
      record.load_from_file
      record
    end

    def self.build_record_path(name)
      backspin_dir = Backspin.configuration.backspin_dir
      backspin_dir.mkpath

      File.join(backspin_dir, "#{name}.yml")
    end

    def self.create(name)
      path = build_record_path(name)
      new(path)
    end

    def initialize(path)
      @path = path
      @commands = []
      @first_recorded_at = nil
      @playback_index = 0
    end

    def add_command(command)
      @commands << command
      @first_recorded_at ||= command.recorded_at
      self
    end

    def save(filter: nil)
      FileUtils.mkdir_p(File.dirname(@path))
      record_data = {
        "first_recorded_at" => @first_recorded_at,
        "format_version" => FORMAT_VERSION,
        "commands" => @commands.map { |cmd| cmd.to_h(filter: filter) }
      }
      File.write(@path, record_data.to_yaml)
    end

    def reload
      @commands = []
      @playback_index = 0
      load_from_file if File.exist?(@path)
      @playback_index = 0  # Reset again after loading to ensure it's at 0
    end

    def exists?
      File.exist?(@path)
    end

    def empty?
      @commands.empty?
    end

    def size
      @commands.size
    end

    def next_command
      if @playback_index >= @commands.size
        raise NoMoreRecordingsError, "No more recordings available for replay"
      end

      command = @commands[@playback_index]
      @playback_index += 1
      command
    end

    def clear
      @commands = []
      @playback_index = 0
    end

    # private

    def load_from_file
      data = YAML.load_file(@path.to_s)

      unless data.is_a?(Hash) && data["format_version"] == "2.0"
        raise RecordFormatError, "Invalid record format: expected format version 2.0"
      end

      @first_recorded_at = data["first_recorded_at"]
      @commands = data["commands"].map { |command_data| Command.from_h(command_data) }
    rescue Psych::SyntaxError => e
      raise RecordFormatError, "Invalid record format: #{e.message}"
    end
  end
end
