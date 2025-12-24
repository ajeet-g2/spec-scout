# frozen_string_literal: true

module SpecScout
  # Final recommendation containing action, confidence, and explanation
  Recommendation = Struct.new(
    :spec_location,   # String: Location of the spec file
    :action,          # Symbol: :replace_factory_strategy, :avoid_db_persistence, etc.
    :from_value,      # String: Current value (e.g., "create(:user)")
    :to_value,        # String: Recommended value (e.g., "build_stubbed(:user)")
    :confidence,      # Symbol: :high, :medium, :low
    :explanation,     # Array: Array of explanation strings
    :agent_results,   # Array: Array of AgentResult objects
    keyword_init: true
  ) do
    VALID_ACTIONS = %i[
      replace_factory_strategy
      avoid_db_persistence
      optimize_queries
      no_action
      review_test_intent
      assess_risk_factors
    ].freeze

    def initialize(**args)
      super
      self.spec_location ||= ''
      self.action ||= :no_action
      self.from_value ||= ''
      self.to_value ||= ''
      self.confidence ||= :low
      self.explanation ||= []
      self.agent_results ||= []
    end

    def valid?
      spec_location.is_a?(String) &&
        VALID_ACTIONS.include?(action) &&
        from_value.is_a?(String) &&
        to_value.is_a?(String) &&
        %i[high medium low].include?(confidence) &&
        explanation.is_a?(Array) &&
        agent_results.is_a?(Array) &&
        agent_results.all? { |result| result.is_a?(AgentResult) }
    end

    def actionable?
      action != :no_action
    end

    def high_confidence?
      confidence == :high
    end

    def medium_confidence?
      confidence == :medium
    end

    def low_confidence?
      confidence == :low
    end
  end
end
