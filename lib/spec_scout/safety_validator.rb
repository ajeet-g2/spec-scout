# frozen_string_literal: true

require 'set'

module SpecScout
  # Safety validation module to ensure no spec file mutations during analysis
  # and prevent auto-application of code changes by default
  class SafetyValidator
    class SafetyViolationError < StandardError; end

    def initialize(config)
      @config = config
      @monitored_files = Set.new
      @original_file_states = {}
    end

    # Monitor spec files to ensure they are not modified during analysis
    def monitor_spec_files(spec_paths)
      return unless @config.enabled?

      spec_paths = Array(spec_paths).compact
      spec_paths.each do |path|
        next unless File.exist?(path)

        @monitored_files.add(path)
        @original_file_states[path] = {
          mtime: File.mtime(path),
          size: File.size(path),
          checksum: file_checksum(path)
        }
      end
    end

    # Validate that no monitored files have been modified
    def validate_no_mutations!
      return unless @config.enabled?

      violations = []

      @monitored_files.each do |path|
        next unless File.exist?(path)

        original_state = @original_file_states[path]
        current_state = {
          mtime: File.mtime(path),
          size: File.size(path),
          checksum: file_checksum(path)
        }

        violations << "File modified during analysis: #{path}" if file_modified?(original_state, current_state)
      end

      return if violations.empty?

      raise SafetyViolationError, "Safety violation detected:\n#{violations.join("\n")}"
    end

    # Ensure no auto-application of code changes
    def prevent_auto_application!
      return unless @config.enabled?

      return unless @config.auto_apply_enabled?

      raise SafetyViolationError,
            'Auto-application of code changes is not allowed by default. Use explicit configuration to enable.'
    end

    # Validate non-blocking operation mode
    def validate_non_blocking_mode!
      return unless @config.enabled?

      # In non-blocking mode, we should never exit with failure unless explicitly configured
      return unless @config.blocking_mode_enabled?

      raise SafetyViolationError,
            'Blocking mode is not allowed by default. Use enforcement mode configuration to enable.'
    end

    # Check if the system is operating in safe mode
    def safe_mode?
      @config.enabled? &&
        !@config.auto_apply_enabled? &&
        !@config.blocking_mode_enabled?
    end

    # Get safety status report
    def safety_status
      {
        safe_mode: safe_mode?,
        monitored_files: @monitored_files.size,
        auto_apply_disabled: !@config.auto_apply_enabled?,
        non_blocking_mode: !@config.blocking_mode_enabled?,
        mutations_detected: mutations_detected?
      }
    end

    private

    def file_checksum(path)
      require 'digest'
      Digest::SHA256.file(path).hexdigest
    rescue StandardError
      nil
    end

    def file_modified?(original, current)
      original[:mtime] != current[:mtime] ||
        original[:size] != current[:size] ||
        (original[:checksum] && current[:checksum] && original[:checksum] != current[:checksum])
    end

    def mutations_detected?
      @monitored_files.any? do |path|
        next false unless File.exist?(path)

        original_state = @original_file_states[path]
        current_state = {
          mtime: File.mtime(path),
          size: File.size(path),
          checksum: file_checksum(path)
        }

        file_modified?(original_state, current_state)
      end
    end
  end
end
