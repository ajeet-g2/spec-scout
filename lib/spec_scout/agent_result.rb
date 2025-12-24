# frozen_string_literal: true

module SpecScout
  VALID_CONFIDENCE_LEVELS = %i[high medium low].freeze

  # Agent output containing recommendation, confidence level, and reasoning
  AgentResult = Struct.new(
    :agent_name,    # Symbol: :database, :factory, :intent, :risk
    :verdict,       # Symbol: :db_unnecessary, :prefer_build_stubbed, etc.
    :confidence,    # Symbol: :high, :medium, :low
    :reasoning,     # String: Human-readable explanation
    :metadata,      # Hash: Additional agent-specific data
    keyword_init: true
  ) do
    def initialize(**args)
      super
      self.agent_name ||= :unknown
      self.verdict ||= :no_verdict
      self.confidence ||= :low
      self.reasoning ||= ''
      self.metadata ||= {}
    end

    def valid?
      agent_name.is_a?(Symbol) &&
        verdict.is_a?(Symbol) &&
        VALID_CONFIDENCE_LEVELS.include?(confidence) &&
        reasoning.is_a?(String) &&
        metadata.is_a?(Hash)
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
