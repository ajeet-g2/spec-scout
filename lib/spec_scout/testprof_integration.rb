# frozen_string_literal: true

require 'test_prof'

module SpecScout
  # Handles TestProf integration, execution, and data extraction
  class TestProfIntegration
    class TestProfError < StandardError; end

    def initialize(config = nil)
      @config = config || ::SpecScout.configuration
      @enabled = false
    end

    # Enable and execute TestProf profiling
    def execute_profiling(_spec_location = nil)
      return nil unless @config.use_test_prof

      begin
        enable_testprof_profilers
        @enabled = true

        # Extract profile data immediately after enabling
        extract_profile_data
      rescue StandardError => e
        raise TestProfError, "Failed to enable TestProf: #{e.message}"
      end
    end

    # Extract structured profile data from TestProf results
    def extract_profile_data
      return {} unless @enabled

      begin
        {
          factory_prof: extract_factory_prof_data,
          event_prof: extract_event_prof_data,
          db_queries: extract_db_query_data
        }
      rescue StandardError => e
        raise TestProfError, "Failed to extract TestProf data: #{e.message}"
      end
    end

    # Check if TestProf is available and properly configured
    def testprof_available?
      defined?(TestProf) && TestProf.respond_to?(:config)
    end

    private

    def enable_testprof_profilers
      raise TestProfError, 'TestProf not available' unless testprof_available?

      # Enable FactoryProf
      TestProf::FactoryProf.init if defined?(TestProf::FactoryProf)

      # Configure TestProf settings
      configure_testprof_settings
    end

    def configure_testprof_settings
      return unless defined?(TestProf)

      # Set up basic TestProf configuration
      TestProf.configure do |config|
        config.output_dir = 'tmp/test_prof'
        config.timestamps = true
      end
    end

    def extract_factory_prof_data
      return {} unless defined?(TestProf::FactoryProf)

      # Extract FactoryProf results if available
      if TestProf::FactoryProf.respond_to?(:stats)
        stats = TestProf::FactoryProf.stats
        return {} unless stats

        {
          total_count: stats.values.sum { |s| s[:total] || 0 },
          total_time: stats.values.sum { |s| s[:time] || 0.0 },
          stats: extract_factory_stats_from_hash(stats)
        }
      else
        {}
      end
    rescue StandardError => e
      # Log error but don't fail the entire extraction
      { error: "FactoryProf extraction failed: #{e.message}" }
    end

    def extract_factory_stats_from_hash(stats)
      return {} unless stats.is_a?(Hash)

      result = {}
      stats.each do |factory_name, factory_data|
        result[factory_name.to_sym] = {
          count: factory_data[:total] || factory_data[:count] || 0,
          time: factory_data[:time] || 0.0,
          strategy: detect_factory_strategy(factory_data)
        }
      end
      result
    rescue StandardError
      {}
    end

    def detect_factory_strategy(factory_data)
      # Try to detect if factory used create, build, or build_stubbed
      # This is a simplified detection - real implementation would need
      # more sophisticated analysis of TestProf data
      if factory_data[:create_count]&.positive?
        :create
      elsif factory_data[:build_count]&.positive?
        :build
      else
        :unknown
      end
    end

    def extract_event_prof_data
      return {} unless defined?(TestProf::EventProf)

      # EventProf doesn't have a simple results API like FactoryProf
      # Return empty data for now - this would need to be implemented
      # based on how EventProf actually stores its results
      {}
    rescue StandardError => e
      # Log error but don't fail the entire extraction
      { error: "EventProf extraction failed: #{e.message}" }
    end

    def extract_event_stats(results)
      return {} unless results.respond_to?(:each)

      events = {}
      results.each do |event_name, event_data|
        events[event_name.to_sym] = {
          count: event_data[:count] || 0,
          time: event_data[:time] || 0.0,
          examples: event_data[:examples] || []
        }
      end
      events
    rescue StandardError
      {}
    end

    def extract_db_query_data
      # Extract database query information
      # This would typically come from EventProf sql.active_record events
      # or other TestProf database profiling features

      db_data = {
        total_queries: 0,
        inserts: 0,
        selects: 0,
        updates: 0,
        deletes: 0
      }

      # Try to get SQL event data from EventProf
      event_data = extract_event_prof_data
      if event_data[:events] && event_data[:events][:'sql.active_record']
        sql_events = event_data[:events][:'sql.active_record']
        db_data[:total_queries] = sql_events[:count] || 0

        # Parse examples to categorize query types
        categorize_sql_queries(sql_events[:examples], db_data) if sql_events[:examples]
      end

      db_data
    rescue StandardError => e
      # Return default structure on error
      {
        total_queries: 0,
        inserts: 0,
        selects: 0,
        updates: 0,
        deletes: 0,
        error: "DB query extraction failed: #{e.message}"
      }
    end

    def categorize_sql_queries(examples, db_data)
      examples.each do |example|
        next unless example.is_a?(Hash) && example[:sql]

        sql = example[:sql].to_s.upcase
        case sql
        when /^INSERT/
          db_data[:inserts] += 1
        when /^SELECT/
          db_data[:selects] += 1
        when /^UPDATE/
          db_data[:updates] += 1
        when /^DELETE/
          db_data[:deletes] += 1
        end
      end
    rescue StandardError
      # Ignore categorization errors
    end
  end
end
