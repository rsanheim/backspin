# frozen_string_literal: true

module Backspin
  class RecordFormatError < StandardError; end

  class Record
    FORMAT_VERSION = "4.0"
    attr_reader :path, :snapshot, :recorded_at

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
      @snapshot = nil
      @recorded_at = nil
    end

    def set_snapshot(snapshot)
      @snapshot = snapshot
      @recorded_at ||= snapshot.recorded_at
      self
    end

    def save(filter: nil)
      FileUtils.mkdir_p(File.dirname(@path))
      record_data = {
        "format_version" => FORMAT_VERSION,
        "recorded_at" => @recorded_at,
        "snapshot" => @snapshot&.to_h(filter: filter)
      }
      File.write(@path, record_data.to_yaml)
    end

    def reload
      @snapshot = nil
      @recorded_at = nil
      load_from_file if File.exist?(@path)
    end

    def exists?
      File.exist?(@path)
    end

    def empty?
      @snapshot.nil?
    end

    def clear
      @snapshot = nil
      @recorded_at = nil
    end

    def load_from_file
      data = YAML.load_file(@path.to_s)

      unless data.is_a?(Hash) && data["format_version"] == FORMAT_VERSION
        raise RecordFormatError, "Invalid record format: expected format version #{FORMAT_VERSION}"
      end

      snapshot_data = data["snapshot"]
      unless snapshot_data.is_a?(Hash)
        raise RecordFormatError, "Invalid record format: missing snapshot"
      end

      @recorded_at = data["recorded_at"]
      @snapshot = Snapshot.from_h(snapshot_data)
    rescue Psych::SyntaxError => e
      raise RecordFormatError, "Invalid record format: #{e.message}"
    end
  end
end
