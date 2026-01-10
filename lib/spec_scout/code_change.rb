# frozen_string_literal: true

module SpecScout
  # Represents a specific code change that can be applied to a file
  # Used in v2.0 for automated file editing capabilities
  CodeChange = Struct.new(
    :file_path,
    :line_number,
    :original_code,
    :modified_code,
    :change_type,
    :confidence,
    :reasoning,
    keyword_init: true
  ) do
    # Valid change types for code modifications
    VALID_CHANGE_TYPES = %i[
      factory_strategy
      database_optimization
      test_structure
      performance_optimization
      risk_mitigation
    ].freeze

    # Initialize with validation
    def initialize(**args)
      super
      validate!
      freeze
    end

    # Validate the code change structure
    def validate!
      validate_required_fields!
      validate_change_type!
      validate_confidence!
      validate_file_path!
      validate_line_number!
    end

    # Convert to hash for serialization
    def to_h
      {
        file_path: file_path,
        line_number: line_number,
        original_code: original_code,
        modified_code: modified_code,
        change_type: change_type,
        confidence: confidence,
        reasoning: reasoning
      }
    end

    # Convert to JSON
    def to_json(*args)
      to_h.to_json(*args)
    end

    # Create from hash
    def self.from_h(hash)
      new(**hash.transform_keys(&:to_sym))
    end

    # Create from JSON
    def self.from_json(json_string)
      hash = JSON.parse(json_string, symbolize_names: true)
      from_h(hash)
    end

    # Check if this change affects the same location as another
    def conflicts_with?(other_change)
      return false unless other_change.is_a?(CodeChange)
      return false unless file_path == other_change.file_path

      # Check for line number conflicts (same line or overlapping ranges)
      line_number == other_change.line_number
    end

    # Generate a diff-like representation
    def to_diff
      [
        "--- #{file_path}:#{line_number}",
        "- #{original_code.strip}",
        "+ #{modified_code.strip}",
        "# #{reasoning}"
      ].join("\n")
    end

    # Check if the change is safe to apply
    def safe_to_apply?
      confidence == :high &&
        !original_code.nil? &&
        !modified_code.nil? &&
        original_code != modified_code
    end

    private

    def validate_required_fields!
      required_fields = %i[file_path original_code modified_code change_type confidence reasoning]
      missing_fields = required_fields.select { |field| send(field).nil? }

      return if missing_fields.empty?

      raise ArgumentError, "Missing required fields: #{missing_fields.join(', ')}"
    end

    def validate_change_type!
      return if VALID_CHANGE_TYPES.include?(change_type)

      raise ArgumentError, "Invalid change_type: #{change_type}. Must be one of: #{VALID_CHANGE_TYPES.join(', ')}"
    end

    def validate_confidence!
      return if VALID_CONFIDENCE_LEVELS.include?(confidence)

      raise ArgumentError, "Invalid confidence: #{confidence}. Must be one of: #{VALID_CONFIDENCE_LEVELS.join(', ')}"
    end

    def validate_file_path!
      return if file_path.is_a?(String) && !file_path.empty?

      raise ArgumentError, 'file_path must be a non-empty string'
    end

    def validate_line_number!
      return if line_number.nil? || (line_number.is_a?(Integer) && line_number.positive?)

      raise ArgumentError, 'line_number must be a positive integer or nil'
    end
  end
end
