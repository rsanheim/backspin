# frozen_string_literal: true

module Backspin
  class RecordFormatError < StandardError; end

  class Record
    FORMAT_VERSION = "4.1"
    SUPPORTED_FORMAT_VERSIONS = ["4.0", FORMAT_VERSION].freeze
    attr_reader :path, :snapshot, :first_recorded_at, :recorded_at, :record_count

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
      @first_recorded_at = nil
      @recorded_at = nil
      @record_count = nil
    end

    def set_snapshot(snapshot)
      @snapshot = snapshot
      snapshot_recorded_at = snapshot.recorded_at || Time.now.iso8601
      @first_recorded_at ||= snapshot_recorded_at
      @recorded_at = snapshot_recorded_at
      self
    end

    def save(filter: nil)
      FileUtils.mkdir_p(File.dirname(@path))
      snapshot_data = @snapshot&.to_h
      snapshot_data = filter.call(deep_dup(snapshot_data)) if snapshot_data && filter
      next_record_count = (@record_count || 0) + 1
      record_data = {
        "format_version" => FORMAT_VERSION,
        "first_recorded_at" => @first_recorded_at,
        "recorded_at" => @recorded_at,
        "record_count" => next_record_count,
        "snapshot" => snapshot_data
      }
      File.write(@path, record_data.to_yaml)
      @record_count = next_record_count
    end

    def reload
      @snapshot = nil
      @first_recorded_at = nil
      @recorded_at = nil
      @record_count = nil
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
      @first_recorded_at = nil
      @recorded_at = nil
      @record_count = nil
    end

    def load_from_file
      data = YAML.load_file(@path.to_s)

      unless data.is_a?(Hash) && SUPPORTED_FORMAT_VERSIONS.include?(data["format_version"])
        raise RecordFormatError, "Invalid record format: expected format version #{FORMAT_VERSION}"
      end

      snapshot_data = data["snapshot"]
      unless snapshot_data.is_a?(Hash)
        raise RecordFormatError, "Invalid record format: missing snapshot"
      end

      format_version = data["format_version"]
      @recorded_at = data["recorded_at"] || snapshot_data["recorded_at"]
      if format_version == FORMAT_VERSION
        @first_recorded_at = data["first_recorded_at"]
        @record_count = data["record_count"]
      else
        # Backfill metadata for v4.0 records.
        @first_recorded_at = data["first_recorded_at"] || @recorded_at
        @record_count = data.fetch("record_count", 1)
      end
      validate_metadata!
      @snapshot = Snapshot.from_h(snapshot_data)
    rescue Psych::SyntaxError => e
      raise RecordFormatError, "Invalid record format: #{e.message}"
    end

    private

    def validate_metadata!
      unless @first_recorded_at.is_a?(String) && !@first_recorded_at.empty?
        raise RecordFormatError, "Invalid record format: missing first_recorded_at"
      end

      unless @recorded_at.is_a?(String) && !@recorded_at.empty?
        raise RecordFormatError, "Invalid record format: missing recorded_at"
      end

      unless @record_count.is_a?(Integer) && @record_count.positive?
        raise RecordFormatError, "Invalid record format: record_count must be a positive integer"
      end
    end

    def deep_dup(value)
      case value
      when Hash
        value.transform_values { |entry| deep_dup(entry) }
      when Array
        value.map { |entry| deep_dup(entry) }
      when String
        value.dup
      else
        value
      end
    end
  end
end
