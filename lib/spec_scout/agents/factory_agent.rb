# frozen_string_literal: true

require_relative '../base_agent'

module SpecScout
  module Agents
    # Agent that evaluates FactoryBot strategy appropriateness and recommends optimizations
    class FactoryAgent < BaseAgent
      # Verdict types for factory strategy optimization
      VERDICTS = {
        prefer_build_stubbed: :prefer_build_stubbed,
        create_required: :create_required,
        strategy_optimal: :strategy_optimal
      }.freeze

      def evaluate
        return no_factory_data_result unless factories_present?

        factory_analysis = analyze_factory_usage

        verdict, confidence, reasoning = determine_recommendation(factory_analysis)

        create_result(
          verdict: verdict,
          confidence: confidence,
          reasoning: reasoning,
          metadata: factory_analysis
        )
      end

      private

      def analyze_factory_usage
        create_count = 0
        build_stubbed_count = 0
        total_factories = 0
        factory_details = {}
        association_access_detected = false

        profile_data.factories.each do |factory_name, factory_data|
          next unless factory_data.is_a?(Hash)

          strategy = factory_data[:strategy] || :unknown
          count = factory_data[:count] || 0
          associations = factory_data[:associations] || []

          total_factories += count
          factory_details[factory_name] = factory_data

          # Check for association access patterns
          association_access_detected = true if associations.any? || association_indicators?(factory_data)

          case strategy
          when :create
            create_count += count
          when :build_stubbed
            build_stubbed_count += count
          end
        end

        {
          create_count: create_count,
          build_stubbed_count: build_stubbed_count,
          total_factories: total_factories,
          factory_details: factory_details,
          database_writes: profile_data.db[:inserts] || 0,
          association_access_detected: association_access_detected
        }
      end

      def determine_recommendation(analysis)
        create_count = analysis[:create_count]
        build_stubbed_count = analysis[:build_stubbed_count]
        database_writes = analysis[:database_writes]
        association_access = analysis[:association_access_detected]

        if prefer_build_stubbed?(create_count, database_writes, association_access)
          prefer_build_stubbed_result(create_count)
        elsif create_required_association?(create_count, association_access)
          create_required_association_result
        elsif create_required_db?(create_count, database_writes)
          create_required_db_result(database_writes, create_count)
        elsif strategy_optimal?(build_stubbed_count, create_count)
          strategy_optimal_result(build_stubbed_count)
        else
          mixed_usage_result
        end
      end

      def prefer_build_stubbed?(create_count, database_writes, association_access)
        create_count.positive? && database_writes.zero? && !association_access
      end

      def create_required_association?(create_count, association_access)
        create_count.positive? && association_access
      end

      def create_required_db?(create_count, database_writes)
        create_count.positive? && database_writes.positive?
      end

      def strategy_optimal?(build_stubbed_count, create_count)
        build_stubbed_count.positive? && create_count.zero?
      end

      def prefer_build_stubbed_result(create_count)
        [
          VERDICTS[:prefer_build_stubbed],
          :medium,
          "Using create strategy (#{create_count} factories) but no database writes or association access detected. " \
          'Consider using build_stubbed for better performance.'
        ]
      end

      def create_required_association_result
        [
          VERDICTS[:create_required],
          :medium,
          'Using create strategy with association access patterns detected. ' \
          'Factory persistence may be necessary for association handling.'
        ]
      end

      def create_required_db_result(database_writes, _create_count)
        [
          VERDICTS[:create_required],
          :medium,
          "Using create strategy with database writes (#{database_writes} inserts). " \
          'Factory persistence appears necessary.'
        ]
      end

      def strategy_optimal_result(build_stubbed_count)
        [
          VERDICTS[:strategy_optimal],
          :high,
          "Already using build_stubbed strategy (#{build_stubbed_count} factories). " \
          'Factory strategy is optimized.'
        ]
      end

      def mixed_usage_result
        [
          VERDICTS[:strategy_optimal],
          :low,
          'Mixed factory usage pattern. Current strategy appears reasonable.'
        ]
      end

      def no_factory_data_result
        create_result(
          verdict: VERDICTS[:strategy_optimal],
          confidence: :low,
          reasoning: 'No factory usage data available for analysis.',
          metadata: { no_data: true }
        )
      end

      # Helper method to detect association access patterns in factory data
      def association_indicators?(factory_data)
        traits_with_association?(factory_data) ||
          attributes_with_foreign_key?(factory_data) ||
          build_strategy_with_associations?(factory_data)
      end

      def traits_with_association?(factory_data)
        factory_data[:traits]&.any? { |trait| trait.to_s.include?('with_') }
      end

      def attributes_with_foreign_key?(factory_data)
        factory_data[:attributes]&.keys&.any? { |attr| attr.to_s.end_with?('_id') }
      end

      def build_strategy_with_associations?(factory_data)
        factory_data[:build_strategy] == :create && factory_data[:associations_count].to_i.positive?
      end
    end
  end
end
