# frozen_string_literal: true

require_relative '../../base_optimizer'

module SpecScout
  module Optimizers
    module RuleBased
      # Optimizer that classifies test intent and behavior patterns to determine
      # if tests are behaving as unit or integration tests
      class IntentOptimiser < BaseOptimizer
        # Verdict types for test intent classification
        VERDICTS = {
          unit_test_behavior: :unit_test_behavior,
          integration_test_behavior: :integration_test_behavior,
          intent_unclear: :intent_unclear
        }.freeze

        # File path patterns that indicate different test types
        UNIT_TEST_PATTERNS = [
          %r{spec/models/},
          %r{spec/lib/},
          %r{spec/services/},
          %r{spec/helpers/},
          %r{spec/presenters/},
          %r{spec/decorators/},
          %r{spec/serializers/},
          %r{spec/validators/},
          %r{spec/concerns/},
          %r{spec/jobs/}
        ].freeze

        INTEGRATION_TEST_PATTERNS = [
          %r{spec/features/},
          %r{spec/integration/},
          %r{spec/system/},
          %r{spec/requests/},
          %r{spec/controllers/},
          %r{spec/routing/},
          %r{spec/views/},
          %r{spec/mailers/}
        ].freeze

        def evaluate
          return no_location_data_result if profile_data.example_location.empty?

          file_location_signal = analyze_file_location
          runtime_behavior_signal = analyze_runtime_behavior
          database_usage_signal = analyze_database_usage
          factory_usage_signal = analyze_factory_usage

          verdict, confidence, reasoning = determine_intent(
            file_location: file_location_signal,
            runtime_behavior: runtime_behavior_signal,
            database_usage: database_usage_signal,
            factory_usage: factory_usage_signal
          )

          create_result(
            verdict: verdict,
            confidence: confidence,
            reasoning: reasoning,
            metadata: {
              file_location_signal: file_location_signal,
              runtime_behavior_signal: runtime_behavior_signal,
              database_usage_signal: database_usage_signal,
              factory_usage_signal: factory_usage_signal,
              runtime_ms: profile_data.runtime_ms
            }
          )
        end

        private

        def analyze_file_location
          location = profile_data.example_location.downcase

          if UNIT_TEST_PATTERNS.any? { |pattern| location.match?(pattern) }
            :unit_test_location
          elsif INTEGRATION_TEST_PATTERNS.any? { |pattern| location.match?(pattern) }
            :integration_test_location
          else
            :unclear_location
          end
        end

        def analyze_runtime_behavior
          runtime = profile_data.runtime_ms

          case runtime
          when 0..10
            :fast_execution # Typical unit test speed
          when 11..100
            :moderate_execution # Could be either
          else
            :slow_execution # Likely integration test
          end
        end

        def analyze_database_usage
          return :no_database_data unless database_operations_present?

          total_queries = profile_data.db[:total_queries] || 0
          profile_data.db[:inserts] || 0

          case total_queries
          when 0..2
            :minimal_database # Unit test pattern
          when 3..10
            :moderate_database # Could be either
          else
            :heavy_database # Integration test pattern
          end
        end

        def analyze_factory_usage
          return :no_factory_data unless factories_present?

          factory_count = profile_data.factories.values.sum { |factory| factory[:count] || 0 }
          create_usage = profile_data.factories.values.count { |factory| factory[:strategy] == :create }

          if factory_count <= 1 && create_usage.zero?
            :minimal_factories # Unit test pattern
          elsif factory_count > 5 || create_usage > 3
            :heavy_factories # Integration test pattern
          else
            :moderate_factories # Could be either
          end
        end

        def determine_intent(file_location:, runtime_behavior:, database_usage:, factory_usage:)
          unit_signals = count_unit_signals(file_location, runtime_behavior, database_usage, factory_usage)
          integration_signals = count_integration_signals(file_location, runtime_behavior, database_usage,
                                                          factory_usage)

          if unit_signals >= 3
            unit_test_result(unit_signals, integration_signals)
          elsif integration_signals >= 3
            integration_test_result(unit_signals, integration_signals)
          elsif unit_signals >= 2 && integration_signals.zero?
            unit_test_result_medium_confidence(unit_signals, integration_signals)
          elsif integration_signals >= 2 && unit_signals.zero?
            integration_test_result_medium_confidence(unit_signals, integration_signals)
          elsif unit_signals > integration_signals && unit_signals >= 1
            unit_test_result_medium_confidence(unit_signals, integration_signals)
          elsif integration_signals > unit_signals && integration_signals >= 1
            integration_test_result_medium_confidence(unit_signals, integration_signals)
          else
            unclear_intent_result(unit_signals, integration_signals)
          end
        end

        def count_unit_signals(file_location, runtime_behavior, database_usage, factory_usage)
          signals = 0
          signals += 1 if file_location == :unit_test_location
          signals += 1 if runtime_behavior == :fast_execution
          signals += 1 if database_usage == :minimal_database
          signals += 1 if factory_usage == :minimal_factories
          signals
        end

        def count_integration_signals(file_location, runtime_behavior, database_usage, factory_usage)
          signals = 0
          signals += 1 if file_location == :integration_test_location
          signals += 1 if runtime_behavior == :slow_execution
          signals += 1 if database_usage == :heavy_database
          signals += 1 if factory_usage == :heavy_factories
          signals
        end

        def unit_test_result(unit_signals, integration_signals)
          [
            VERDICTS[:unit_test_behavior],
            :high,
            "Strong unit test behavior detected (#{unit_signals} unit signals, #{integration_signals} integration signals). " \
            'Test appears to focus on isolated component behavior.'
          ]
        end

        def integration_test_result(unit_signals, integration_signals)
          [
            VERDICTS[:integration_test_behavior],
            :high,
            "Strong integration test behavior detected (#{integration_signals} integration signals, #{unit_signals} unit signals). " \
            'Test appears to cross integration boundaries.'
          ]
        end

        def unit_test_result_medium_confidence(unit_signals, integration_signals)
          [
            VERDICTS[:unit_test_behavior],
            :medium,
            "Likely unit test behavior (#{unit_signals} unit signals, #{integration_signals} integration signals). " \
            'Some mixed signals present but unit test patterns dominate.'
          ]
        end

        def integration_test_result_medium_confidence(unit_signals, integration_signals)
          [
            VERDICTS[:integration_test_behavior],
            :medium,
            "Likely integration test behavior (#{integration_signals} integration signals, #{unit_signals} unit signals). " \
            'Some mixed signals present but integration test patterns dominate.'
          ]
        end

        def unclear_intent_result(unit_signals, integration_signals)
          [
            VERDICTS[:intent_unclear],
            :low,
            "Mixed behavioral signals detected (#{unit_signals} unit signals, #{integration_signals} integration signals). " \
            'Unable to clearly classify test intent.'
          ]
        end

        def no_location_data_result
          create_result(
            verdict: VERDICTS[:intent_unclear],
            confidence: :low,
            reasoning: 'No spec location data available for intent analysis.',
            metadata: { no_data: true }
          )
        end
      end
    end
  end
end
