# frozen_string_literal: true

require 'json'

module SpecScout
  # Collection class for managing multiple CodeChange objects
  # Provides validation, conflict detection, and serialization capabilities
  class CodeChangeCollection
    include Enumerable

    attr_reader :changes

    def initialize(changes = [])
      @changes = []
      changes.each { |change| add_change(change) }
    end

    # Add a code change to the collection
    def add_change(change)
      raise ArgumentError, "Expected CodeChange, got #{change.class}" unless change.is_a?(CodeChange)

      validate_no_conflicts!(change)
      @changes << change
      self
    end

    # Remove a code change from the collection
    def remove_change(change)
      @changes.delete(change)
      self
    end

    # Iterate over changes
    def each(&block)
      @changes.each(&block)
    end

    # Get changes by file path
    def changes_for_file(file_path)
      @changes.select { |change| change.file_path == file_path }
    end

    # Get changes by change type
    def changes_by_type(change_type)
      @changes.select { |change| change.change_type == change_type }
    end

    # Get changes by confidence level
    def changes_by_confidence(confidence)
      @changes.select { |change| change.confidence == confidence }
    end

    # Get only high-confidence changes
    def high_confidence_changes
      changes_by_confidence(:high)
    end

    # Get only safe changes
    def safe_changes
      @changes.select(&:safe_to_apply?)
    end

    # Check if collection is empty
    def empty?
      @changes.empty?
    end

    # Get count of changes
    def count
      @changes.count
    end
    alias size count
    alias length count

    # Get all affected file paths
    def affected_files
      @changes.map(&:file_path).uniq.sort
    end

    # Validate all changes for conflicts
    def validate_no_conflicts!
      @changes.combination(2).each do |change1, change2|
        if change1.conflicts_with?(change2)
          raise ArgumentError, "Conflicting changes detected for #{change1.file_path}:#{change1.line_number}"
        end
      end
    end

    # Convert to array of hashes
    def to_a
      @changes.map(&:to_h)
    end

    # Convert to JSON
    def to_json(*args)
      to_a.to_json(*args)
    end

    # Create from array of hashes
    def self.from_a(array)
      changes = array.map { |hash| CodeChange.from_h(hash) }
      new(changes)
    end

    # Create from JSON
    def self.from_json(json_string)
      array = JSON.parse(json_string, symbolize_names: true)
      from_a(array)
    end

    # Generate summary statistics
    def summary
      {
        total_changes: count,
        by_confidence: {
          high: changes_by_confidence(:high).count,
          medium: changes_by_confidence(:medium).count,
          low: changes_by_confidence(:low).count
        },
        by_type: CHANGE_TYPE_COUNTS,
        affected_files: affected_files.count,
        safe_changes: safe_changes.count
      }
    end

    # Generate a diff-like representation of all changes
    def to_diff
      grouped_changes = @changes.group_by(&:file_path)

      grouped_changes.map do |file_path, file_changes|
        file_diff = ["=== #{file_path} ==="]
        file_diff += file_changes.sort_by(&:line_number).map(&:to_diff)
        file_diff.join("\n")
      end.join("\n\n")
    end

    private

    def validate_no_conflicts!(new_change)
      @changes.each do |existing_change|
        if existing_change.conflicts_with?(new_change)
          raise ArgumentError,
                "Change conflicts with existing change for #{new_change.file_path}:#{new_change.line_number}"
        end
      end
    end

    def CHANGE_TYPE_COUNTS
      CodeChange::VALID_CHANGE_TYPES.each_with_object({}) do |type, hash|
        hash[type] = changes_by_type(type).count
      end
    end
  end
end
