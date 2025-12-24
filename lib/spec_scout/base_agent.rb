# frozen_string_literal: true

module SpecScout
  # Abstract base class for all analysis agents
  class BaseAgent
    attr_reader :profile_data

    def initialize(profile_data)
      @profile_data = profile_data
      validate_profile_data!
    end

    # Abstract method to be implemented by subclasses
    # Returns an AgentResult with verdict, confidence, and reasoning
    def evaluate
      raise NotImplementedError, 'Subclasses must implement #evaluate'
    end

    # Agent name for identification
    def agent_name
      class_name = self.class.name || 'UnknownAgent'
      class_name.split('::').last.downcase.gsub('agent', '').to_sym
    end

    protected

    # Helper method to create AgentResult
    def create_result(verdict:, confidence:, reasoning:, metadata: {})
      AgentResult.new(
        agent_name: agent_name,
        verdict: verdict,
        confidence: confidence,
        reasoning: reasoning,
        metadata: metadata
      )
    end

    # Validate confidence level
    def validate_confidence(confidence)
      return if AgentResult::VALID_CONFIDENCE_LEVELS.include?(confidence)

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
