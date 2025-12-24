# frozen_string_literal: true

require_relative '../base_agent'

module SpecScout
  module Agents
    # Agent that analyzes database usage patterns and identifies unnecessary persistence
    class DatabaseAgent < BaseAgent
      # Verdict types for database optimization
      VERDICTS = {
        db_unnecessary: :db_unnecessary,
        db_required: :db_required,
        db_unclear: :db_unclear
      }.freeze

      def evaluate
        return no_database_data_result unless database_operations_present?

        insert_count = profile_data.db[:inserts] || 0
        select_count = profile_data.db[:selects] || 0
        total_queries = profile_data.db[:total_queries] || 0

        verdict, confidence, reasoning = analyze_database_usage(
          insert_count: insert_count,
          select_count: select_count,
          total_queries: total_queries
        )

        create_result(
          verdict: verdict,
          confidence: confidence,
          reasoning: reasoning,
          metadata: {
            insert_count: insert_count,
            select_count: select_count,
            total_queries: total_queries
          }
        )
      end

      private

      def analyze_database_usage(insert_count:, select_count:, total_queries:)
        if no_db_writes_and_minimal_reads?(insert_count, select_count)
          db_unnecessary_minimal_reads_result(select_count)
        elsif no_db_writes_but_some_reads?(insert_count, select_count)
          db_unnecessary_some_reads_result(select_count)
        elsif db_writes_present?(insert_count)
          db_required_result(insert_count)
        else
          db_unclear_result(total_queries)
        end
      end

      def no_db_writes_and_minimal_reads?(insert_count, select_count)
        insert_count.zero? && select_count <= 1
      end

      def no_db_writes_but_some_reads?(insert_count, select_count)
        insert_count.zero? && select_count > 1
      end

      def db_writes_present?(insert_count)
        insert_count.positive?
      end

      def db_unnecessary_minimal_reads_result(select_count)
        [
          VERDICTS[:db_unnecessary],
          :high,
          "No database writes detected and minimal reads (#{select_count}). " \
          'Consider using build_stubbed or avoiding database persistence.'
        ]
      end

      def db_unnecessary_some_reads_result(select_count)
        [
          VERDICTS[:db_unnecessary],
          :medium,
          "No database writes detected but #{select_count} reads. " \
          'Database persistence may be unnecessary.'
        ]
      end

      def db_required_result(insert_count)
        [
          VERDICTS[:db_required],
          :high,
          "Database writes detected (#{insert_count} inserts). " \
          'Database persistence appears necessary.'
        ]
      end

      def db_unclear_result(total_queries)
        [
          VERDICTS[:db_unclear],
          :low,
          "Mixed database usage pattern (#{total_queries} total queries). " \
          'Unable to determine clear optimization opportunity.'
        ]
      end

      def no_database_data_result
        create_result(
          verdict: VERDICTS[:db_unclear],
          confidence: :low,
          reasoning: 'No database usage data available for analysis.',
          metadata: { no_data: true }
        )
      end
    end
  end
end
