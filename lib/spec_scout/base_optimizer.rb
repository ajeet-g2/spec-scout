# frozen_string_literal: true

require_relative 'optimizer_result'

module SpecScout
  # Abstract base class for all analysis optimizers
  class BaseOptimizer
    attr_reader :profile_data

    def initialize(profile_data)
      @profile_data = profile_data
      validate_profile_data!
    end

    # Abstract method to be implemented by subclasses
    # Returns an OptimizerResult with verdict, confidence, and reasoning
    def evaluate
      raise NotImplementedError, 'Subclasses must implement #evaluate'
    end

    # Optimizer name for identification
    def optimizer_name
      class_name = self.class.name || 'UnknownOptimizer'
      class_name.split('::').last.downcase.gsub('optimiser', '').to_sym
    end

    protected

    # Helper method to create OptimizerResult
    def create_result(verdict:, confidence:, reasoning:, metadata: {})
      OptimizerResult.new(
        optimizer_name: optimizer_name,
        verdict: verdict,
        confidence: confidence,
        reasoning: reasoning,
        metadata: metadata
      )
    end

    # Validate confidence level
    def validate_confidence(confidence)
      return if OptimizerResult::VALID_CONFIDENCE_LEVELS.include?(confidence)

      raise ArgumentError, "Invalid confidence level: #{confidence}"
    end

    # Check if database operations are present
    def database_operations_present?
      return false unless profile_data.db.is_a?(Hash)

      total_queries = profile_data.db[:total_queries] || 0
      inserts = profile_data.db[:inserts] || 0

      total_queries.positive? || inserts.positive?
    end

    # Check if factories are present
    def factories_present?
      return false unless profile_data.factories.is_a?(Hash)

      profile_data.factories.any?
    end

    private

    def validate_profile_data!
      raise ArgumentError, "Expected ProfileData, got #{profile_data.class}" unless profile_data.is_a?(ProfileData)

      return if profile_data.valid?

      raise ArgumentError, 'Invalid ProfileData structure'
    end
  end
end
