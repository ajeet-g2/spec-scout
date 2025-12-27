# frozen_string_literal: true

require 'json'
require 'time'

module SpecScout
  # Formats recommendations and analysis results into human-readable console output
  # and structured JSON format
  class OutputFormatter
    CONFIDENCE_SYMBOLS = {
      high: '✔',
      medium: '⚠',
      low: '?'
    }.freeze

    ACTION_SYMBOLS = {
      replace_factory_strategy: '✔',
      avoid_db_persistence: '✔',
      optimize_queries: '✔',
      no_action: '—',
      review_test_intent: '⚠',
      assess_risk_factors: '⚠'
    }.freeze

    def initialize(recommendation, profile_data)
      @recommendation = recommendation
      @profile_data = profile_data
      validate_inputs!
    end

    # Generate human-readable console output
    def format_recommendation
      output = []

      output << format_header
      output << format_spec_location
      output << ''
      output << format_profiling_summary
      output << ''
      output << format_agent_opinions
      output << ''
      output << format_final_recommendation

      output.join("\n")
    end

    # Generate structured JSON output
    def format_json
      json_data = {
        spec_location: recommendation.spec_location,
        action: recommendation.action.to_s,
        from_value: recommendation.from_value,
        to_value: recommendation.to_value,
        confidence: recommendation.confidence.to_s,
        explanation: recommendation.explanation,
        agent_results: format_agent_results_json,
        profile_data: format_profile_data_json,
        metadata: {
          timestamp: Time.now.iso8601,
          spec_scout_version: VERSION
        }
      }

      JSON.pretty_generate(json_data)
    end

    private

    attr_reader :recommendation, :profile_data

    def validate_inputs!
      unless recommendation.is_a?(Recommendation) && recommendation.valid?
        raise ArgumentError, 'Invalid recommendation provided'
      end

      return if profile_data.is_a?(ProfileData) && profile_data.valid?

      raise ArgumentError, 'Invalid profile data provided'
    end

    def format_header
      confidence_symbol = CONFIDENCE_SYMBOLS[recommendation.confidence]
      "#{confidence_symbol} Spec Scout Recommendation"
    end

    def format_spec_location
      recommendation.spec_location
    end

    def format_profiling_summary
      lines = ['Summary:']

      # Factory usage summary
      if profile_data.factories.any?
        factory_summary = format_factory_summary
        lines << "- #{factory_summary}" if factory_summary
      end

      # Database usage summary
      if profile_data.db.any?
        db_summary = format_db_summary
        lines << "- #{db_summary}" if db_summary
      end

      # Runtime summary
      lines << "- Runtime: #{profile_data.runtime_ms}ms" if profile_data.runtime_ms.positive?

      # Spec type
      lines << "- Type: #{profile_data.spec_type} spec" if profile_data.spec_type != :unknown

      lines.join("\n")
    end

    def format_factory_summary
      return nil unless profile_data.factories.is_a?(Hash) && profile_data.factories.any?

      factory_parts = []
      profile_data.factories.each do |factory_name, factory_info|
        next unless factory_info.is_a?(Hash)

        strategy = factory_info[:strategy] || 'unknown'
        count = factory_info[:count] || 1
        count_text = count > 1 ? " (#{count}x)" : ''
        factory_parts << "Factory :#{factory_name} used `#{strategy}`#{count_text}"
      end

      factory_parts.join(', ')
    end

    def format_db_summary
      return nil unless profile_data.db.is_a?(Hash) && profile_data.db.any?

      db_parts = []

      if profile_data.db[:inserts]
        inserts = profile_data.db[:inserts]
        db_parts << "DB inserts: #{inserts}"
      end

      if profile_data.db[:selects]
        selects = profile_data.db[:selects]
        db_parts << "selects: #{selects}"
      end

      if profile_data.db[:total_queries]
        total = profile_data.db[:total_queries]
        db_parts << "Total queries: #{total}"
      end

      db_parts.join(', ')
    end

    def format_agent_opinions
      return 'Agent Signals:\n- No agent results available' if recommendation.agent_results.empty?

      lines = ['Agent Signals:']

      recommendation.agent_results.each do |agent_result|
        agent_line = format_agent_opinion(agent_result)
        lines << "- #{agent_line}"
      end

      lines.join("\n")
    end

    def format_agent_opinion(agent_result)
      agent_name = humanize_agent_name(agent_result.agent_name)
      verdict = humanize_verdict(agent_result.verdict)
      confidence = agent_result.confidence.to_s.upcase
      confidence_symbol = CONFIDENCE_SYMBOLS[agent_result.confidence]

      "#{agent_name}: #{verdict} (#{confidence_symbol} #{confidence})"
    end

    def humanize_agent_name(agent_name)
      case agent_name
      when :database
        'Database Agent'
      when :factory
        'Factory Agent'
      when :intent
        'Intent Agent'
      when :risk
        'Risk Agent'
      else
        agent_name.to_s.split('_').map(&:capitalize).join(' ')
      end
    end

    def humanize_verdict(verdict)
      case verdict
      when :db_unnecessary
        'DB unnecessary'
      when :db_required
        'DB required'
      when :db_unclear
        'DB usage unclear'
      when :prefer_build_stubbed
        'prefer build_stubbed'
      when :create_required
        'create required'
      when :strategy_optimal
        'strategy optimal'
      when :unit_test_behavior
        'unit test behavior'
      when :integration_test_behavior
        'integration test behavior'
      when :intent_unclear
        'intent unclear'
      when :safe_to_optimize
        'safe to optimize'
      when :potential_side_effects
        'potential side effects'
      when :high_risk
        'high risk detected'
      when :no_verdict
        'no verdict'
      else
        verdict.to_s.gsub('_', ' ')
      end
    end

    def format_final_recommendation
      lines = ['Final Recommendation:']

      action_symbol = ACTION_SYMBOLS[recommendation.action]
      action_text = format_action_text
      confidence_text = format_confidence_text

      lines << "#{action_symbol} #{action_text}"
      lines << "Confidence: #{confidence_text}"

      # Add explanation if available
      if recommendation.explanation.any?
        lines << ''
        lines << 'Reasoning:'
        recommendation.explanation.each do |explanation_line|
          lines << "- #{explanation_line}"
        end
      end

      lines.join("\n")
    end

    def format_action_text
      case recommendation.action
      when :replace_factory_strategy
        if !recommendation.from_value.empty? && !recommendation.to_value.empty?
          "Replace `#{recommendation.from_value}` with `#{recommendation.to_value}`"
        else
          'Replace factory strategy with build_stubbed'
        end
      when :avoid_db_persistence
        if !recommendation.from_value.empty? && !recommendation.to_value.empty?
          "Change from #{recommendation.from_value} to #{recommendation.to_value}"
        else
          'Avoid database persistence - use build_stubbed instead of create'
        end
      when :optimize_queries
        'Optimize database queries'
      when :review_test_intent
        'Review test intent and boundaries'
      when :assess_risk_factors
        'Assess risk factors before optimizing'
      when :no_action
        'No optimization recommended'
      else
        humanize_action(recommendation.action)
      end
    end

    def humanize_action(action)
      action.to_s.gsub('_', ' ').split.map(&:capitalize).join(' ')
    end

    def format_confidence_text
      confidence_symbol = CONFIDENCE_SYMBOLS[recommendation.confidence]
      confidence_name = recommendation.confidence.to_s.upcase

      "#{confidence_symbol} #{confidence_name}"
    end

    def format_agent_results_json
      recommendation.agent_results.map do |agent_result|
        {
          agent_name: agent_result.agent_name.to_s,
          verdict: agent_result.verdict.to_s,
          confidence: agent_result.confidence.to_s,
          reasoning: agent_result.reasoning,
          metadata: agent_result.metadata
        }
      end
    end

    def format_profile_data_json
      {
        example_location: profile_data.example_location,
        spec_type: profile_data.spec_type.to_s,
        runtime_ms: profile_data.runtime_ms,
        factories: profile_data.factories,
        db: profile_data.db,
        events: profile_data.events,
        metadata: profile_data.metadata
      }
    end
  end
end
