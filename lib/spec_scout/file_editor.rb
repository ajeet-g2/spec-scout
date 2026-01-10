# frozen_string_literal: true

require 'fileutils'
require 'tempfile'
require 'digest'

module SpecScout
  # Foundation class for v2.0 file editing capabilities
  # Provides safe file modification with backup and rollback support
  class FileEditor
    class FileEditorError < StandardError; end
    class BackupError < FileEditorError; end
    class SyntaxError < FileEditorError; end
    class RollbackError < FileEditorError; end

    attr_reader :config, :backup_directory

    def initialize(config)
      @config = config
      @backup_directory = config.backup_directory || default_backup_directory
      @applied_changes = []
      ensure_backup_directory_exists!
    end

    # Apply a collection of code changes
    def apply_changes(changes)
      return [] unless file_editing_enabled?

      changes = ensure_change_collection(changes)
      validate_changes!(changes)

      applied_changes = []

      changes.safe_changes.each do |change|
        apply_single_change(change)
        applied_changes << change
        @applied_changes << change
      rescue StandardError => e
        # Rollback any changes applied so far
        rollback_changes(applied_changes) if config.auto_rollback_on_error?
        raise FileEditorError, "Failed to apply change to #{change.file_path}: #{e.message}"
      end

      applied_changes
    end

    # Apply a single code change
    def apply_single_change(change)
      validate_change!(change)

      # Create backup before modification
      backup_path = create_backup(change.file_path)

      begin
        # Read current file content
        content = File.read(change.file_path)

        # Apply the change
        modified_content = apply_change_to_content(content, change)

        # Validate syntax before writing
        validate_syntax!(change.file_path, modified_content)

        # Write modified content
        File.write(change.file_path, modified_content)

        # Verify the change was applied correctly
        verify_change_applied(change)

        backup_path
      rescue StandardError
        # Restore from backup if something went wrong
        restore_from_backup(backup_path, change.file_path) if File.exist?(backup_path)
        raise
      end
    end

    # Create a backup of a file
    def create_backup(file_path)
      raise BackupError, "Cannot backup non-existent file: #{file_path}" unless File.exist?(file_path)

      timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
      file_hash = Digest::MD5.hexdigest(File.read(file_path))[0..7]
      backup_filename = "#{File.basename(file_path)}.#{timestamp}.#{file_hash}.backup"
      backup_path = File.join(@backup_directory, backup_filename)

      FileUtils.cp(file_path, backup_path)
      backup_path
    end

    # Restore a file from backup
    def restore_from_backup(backup_path, target_path)
      raise RollbackError, "Backup file not found: #{backup_path}" unless File.exist?(backup_path)

      FileUtils.cp(backup_path, target_path)
    end

    # Rollback a collection of changes
    def rollback_changes(changes)
      changes = ensure_change_collection(changes)
      rollback_errors = []

      changes.reverse_each do |change|
        rollback_single_change(change)
      rescue StandardError => e
        rollback_errors << "Failed to rollback #{change.file_path}: #{e.message}"
      end

      return if rollback_errors.empty?

      raise RollbackError, "Rollback errors: #{rollback_errors.join('; ')}"
    end

    # Rollback a single change
    def rollback_single_change(change)
      # Find the most recent backup for this file
      backup_path = find_latest_backup(change.file_path)

      raise RollbackError, "No backup found for #{change.file_path}" unless backup_path

      restore_from_backup(backup_path, change.file_path)
      @applied_changes.delete(change)
    end

    # Validate Ruby syntax for a file
    def validate_syntax!(file_path, content = nil)
      content ||= File.read(file_path)

      # Use Ruby's built-in syntax checking
      begin
        RubyVM::InstructionSequence.compile(content)
      rescue SyntaxError => e
        raise SyntaxError, "Syntax error in #{file_path}: #{e.message}"
      end
    end

    # Clean up old backup files
    def cleanup_backups(older_than: 7.days)
      return unless Dir.exist?(@backup_directory)

      cutoff_time = Time.now - older_than

      Dir.glob(File.join(@backup_directory, '*.backup')).each do |backup_file|
        File.delete(backup_file) if File.mtime(backup_file) < cutoff_time
      end
    end

    # Get list of applied changes
    def applied_changes
      @applied_changes.dup
    end

    # Check if file editing is enabled
    def file_editing_enabled?
      config.file_editing_enabled?
    end

    private

    def ensure_change_collection(changes)
      case changes
      when CodeChangeCollection
        changes
      when Array
        CodeChangeCollection.new(changes)
      when CodeChange
        CodeChangeCollection.new([changes])
      else
        raise ArgumentError, "Expected CodeChange, Array, or CodeChangeCollection, got #{changes.class}"
      end
    end

    def validate_changes!(changes)
      raise ArgumentError, 'No changes provided' if changes.empty?

      changes.validate_no_conflicts!
    end

    def validate_change!(change)
      raise ArgumentError, "Expected CodeChange, got #{change.class}" unless change.is_a?(CodeChange)

      raise FileEditorError, "File does not exist: #{change.file_path}" unless File.exist?(change.file_path)

      return if change.safe_to_apply?

      raise FileEditorError, "Change is not safe to apply: #{change.reasoning}"
    end

    def apply_change_to_content(content, change)
      unless content.include?(change.original_code)
        raise FileEditorError, "Original code not found in #{change.file_path}: #{change.original_code}"
      end

      # Replace the original code with modified code
      modified_content = content.gsub(change.original_code, change.modified_code)

      # Verify the replacement was successful
      raise FileEditorError, "No changes were made to #{change.file_path}" if modified_content == content

      modified_content
    end

    def verify_change_applied(change)
      current_content = File.read(change.file_path)

      return if current_content.include?(change.modified_code)

      raise FileEditorError, "Change verification failed for #{change.file_path}"
    end

    def find_latest_backup(file_path)
      filename = File.basename(file_path)
      pattern = File.join(@backup_directory, "#{filename}.*.backup")

      backups = Dir.glob(pattern)
      return nil if backups.empty?

      # Sort by modification time and return the most recent
      backups.max_by { |backup| File.mtime(backup) }
    end

    def ensure_backup_directory_exists!
      FileUtils.mkdir_p(@backup_directory) unless Dir.exist?(@backup_directory)
    end

    def default_backup_directory
      File.join(Dir.pwd, 'tmp', 'spec_scout_backups')
    end
  end
end
