# frozen_string_literal: true

require_relative '../base_agent'

module SpecScout
  module Agents
    # Agent that identifies potentially unsafe optimization scenarios by detecting
    # after_commit callbacks, complex callback chains, and side-effect indicators
    class RiskAgent < BaseAgent
      # Verdict types for risk assessment
      VERDICTS = {
        safe_to_optimize: :safe_to_optimize,
        potential_side_effects: :potential_side_effects,
        high_risk: :high_risk
      }.freeze

      # Event patterns that indicate potential side effects
      SIDE_EFFECT_EVENT_PATTERNS = [
        /after_commit/i,
        /after_create/i,
        /after_update/i,
        /after_save/i,
        /after_destroy/i,
        /callback/i,
        /mailer/i,
        /job/i,
        /queue/i,
        /background/i,
        /sidekiq/i,
        /resque/i,
        /delayed_job/i
      ].freeze

      # Metadata keys that might indicate side effects
      SIDE_EFFECT_METADATA_KEYS = %i[
        callbacks
        after_commit
        after_create
        after_update
        after_save
        mailers
        jobs
        background_jobs
        side_effects
        external_calls
        api_calls
        webhooks
      ].freeze

      # Factory patterns that suggest complex object creation with potential callbacks
      COMPLEX_FACTORY_PATTERNS = [
        /with_.*callback/i,
        /with_.*job/i,
        /with_.*mailer/i,
        /with_.*notification/i,
        /with_.*webhook/i,
        /published/i,
        /activated/i,
        /confirmed/i
      ].freeze

      def evaluate
        callback_indicators = detect_callback_indicators
        side_effect_indicators = detect_side_effect_indicators
        complex_chain_indicators = detect_complex_callback_chains
        factory_risk_indicators = detect_factory_risk_patterns

        risk_score = calculate_risk_score(
          callback_indicators: callback_indicators,
          side_effect_indicators: side_effect_indicators,
          complex_chain_indicators: complex_chain_indicators,
          factory_risk_indicators: factory_risk_indicators
        )

        verdict, confidence, reasoning = determine_risk_level(
          risk_score: risk_score,
          callback_indicators: callback_indicators,
          side_effect_indicators: side_effect_indicators,
          complex_chain_indicators: complex_chain_indicators,
          factory_risk_indicators: factory_risk_indicators
        )

        create_result(
          verdict: verdict,
          confidence: confidence,
          reasoning: reasoning,
          metadata: {
            risk_score: risk_score,
            callback_indicators: callback_indicators,
            side_effect_indicators: side_effect_indicators,
            complex_chain_indicators: complex_chain_indicators,
            factory_risk_indicators: factory_risk_indicators,
            total_risk_factors: callback_indicators.size + side_effect_indicators.size +
                               complex_chain_indicators.size + factory_risk_indicators.size
          }
        )
      end

      private

      def detect_callback_indicators
        indicators = []

        # Check events data for callback-related patterns
        if profile_data.events.is_a?(Hash)
          profile_data.events.each do |event_name, event_data|
            event_string = "#{event_name} #{event_data}".downcase
            SIDE_EFFECT_EVENT_PATTERNS.each do |pattern|
              if event_string.match?(pattern)
                indicators << { type: :event_pattern, pattern: pattern.source, event: event_name }
              end
            end
          end
        end

        # Check metadata for callback indicators
        if profile_data.metadata.is_a?(Hash)
          SIDE_EFFECT_METADATA_KEYS.each do |key|
            if profile_data.metadata.key?(key) && profile_data.metadata[key]
              indicators << { type: :metadata_key, key: key, value: profile_data.metadata[key] }
            end
          end
        end

        indicators
      end

      def detect_side_effect_indicators
        indicators = []

        # High database write activity might indicate complex side effects
        if database_operations_present?
          inserts = profile_data.db[:inserts] || 0
          updates = profile_data.db[:updates] || 0
          deletes = profile_data.db[:deletes] || 0

          total_writes = inserts + updates + deletes
          indicators << { type: :high_db_writes, count: total_writes } if total_writes > 5
        end

        # Multiple factory creation might indicate complex object graphs with callbacks
        if factories_present?
          total_create_factories = profile_data.factories.values.sum do |factory_data|
            factory_data[:strategy] == :create ? (factory_data[:count] || 0) : 0
          end

          if total_create_factories > 3
            indicators << { type: :multiple_create_factories, count: total_create_factories }
          end
        end

        # Long runtime might indicate complex processing with side effects
        indicators << { type: :long_runtime, runtime_ms: profile_data.runtime_ms } if profile_data.runtime_ms > 500

        indicators
      end

      def detect_complex_callback_chains
        indicators = []

        # Check for multiple event types which might indicate callback chains
        if profile_data.events.is_a?(Hash) && profile_data.events.size > 3
          indicators << { type: :multiple_events, count: profile_data.events.size }
        end

        # Check for nested or chained operations in metadata
        if profile_data.metadata.is_a?(Hash) && (profile_data.metadata[:nested_operations] || profile_data.metadata[:chained_callbacks])
          indicators << { type: :nested_operations, metadata: profile_data.metadata }
          end

        indicators
      end

      def detect_factory_risk_patterns
        indicators = []

        return indicators unless factories_present?

        profile_data.factories.each do |factory_name, factory_data|
          next unless factory_data.is_a?(Hash)

          # Check factory traits for risky patterns
          if factory_data[:traits].is_a?(Array)
            factory_data[:traits].each do |trait|
              trait_string = trait.to_s
              COMPLEX_FACTORY_PATTERNS.each do |pattern|
                if trait_string.match?(pattern)
                  indicators << {
                    type: :risky_factory_trait,
                    factory: factory_name,
                    trait: trait,
                    pattern: pattern.source
                  }
                end
              end
            end
          end

          # Check for factories with many associations (potential callback triggers)
          associations_count = factory_data[:associations]&.size || 0
          if associations_count > 2
            indicators << {
              type: :complex_associations,
              factory: factory_name,
              associations_count: associations_count
            }
          end
        end

        indicators
      end

      def calculate_risk_score(callback_indicators:, side_effect_indicators:, complex_chain_indicators:, factory_risk_indicators:)
        score = 0

        # Weight different types of risk indicators
        score += callback_indicators.size * 2      # Callback indicators are high risk
        score += side_effect_indicators.size * 2   # Side effect indicators are medium risk
        score += complex_chain_indicators.size * 2 # Complex chains are medium risk
        score += factory_risk_indicators.size * 1  # Factory risks are lower but still concerning

        score
      end

      def determine_risk_level(risk_score:, callback_indicators:, side_effect_indicators:, complex_chain_indicators:, factory_risk_indicators:)
        total_indicators = callback_indicators.size + side_effect_indicators.size +
                          complex_chain_indicators.size + factory_risk_indicators.size

        if risk_score >= 8 || callback_indicators.size >= 3
          high_risk_result(risk_score, total_indicators)
        elsif risk_score >= 4 || callback_indicators.size >= 2 || total_indicators >= 4
          potential_side_effects_result(risk_score, total_indicators)
        elsif risk_score >= 2 || total_indicators >= 2
          potential_side_effects_medium_confidence_result(risk_score, total_indicators)
        elsif risk_score >= 1 || total_indicators >= 1
          potential_side_effects_low_confidence_result(risk_score, total_indicators)
        else
          safe_to_optimize_result
        end
      end

      def high_risk_result(risk_score, total_indicators)
        [
          VERDICTS[:high_risk],
          :high,
          "High risk optimization scenario detected (risk score: #{risk_score}, #{total_indicators} risk factors). " \
          'Strong indicators of callbacks or side effects present. Optimization not recommended.'
        ]
      end

      def potential_side_effects_result(risk_score, total_indicators)
        [
          VERDICTS[:potential_side_effects],
          :medium,
          "Potential side effects detected (risk score: #{risk_score}, #{total_indicators} risk factors). " \
          'Some indicators suggest callbacks or side effects may be present. Proceed with caution.'
        ]
      end

      def potential_side_effects_medium_confidence_result(risk_score, total_indicators)
        [
          VERDICTS[:potential_side_effects],
          :medium,
          "Potential side effects detected (risk score: #{risk_score}, #{total_indicators} risk factors). " \
          'Multiple indicators suggest callbacks or side effects may be present. Proceed with caution.'
        ]
      end

      def potential_side_effects_low_confidence_result(risk_score, total_indicators)
        [
          VERDICTS[:potential_side_effects],
          :low,
          "Minor risk indicators detected (risk score: #{risk_score}, #{total_indicators} risk factors). " \
          'Weak signals suggest potential side effects. Optimization likely safe but monitor carefully.'
        ]
      end

      def safe_to_optimize_result
        [
          VERDICTS[:safe_to_optimize],
          :high,
          'No risk factors detected. No indicators of callbacks, side effects, or complex chains found. ' \
          'Optimization appears safe to proceed.'
        ]
      end
    end
  end
end