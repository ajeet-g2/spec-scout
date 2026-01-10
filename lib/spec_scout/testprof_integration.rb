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
    def execute_profiling(spec_location = nil)
      return nil unless @config.use_test_prof

      begin
        # Clear any existing TestProf data
        clear_testprof_data

        # Enable TestProf profilers
        enable_testprof_profilers

        # Execute RSpec with the specified spec file
        execute_rspec_with_profiling(spec_location)

        # Extract profile data after test execution
        extract_profile_data
      rescue StandardError => e
        raise TestProfError, "Failed to execute TestProf profiling: #{e.message}"
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

    def clear_testprof_data
      # Clear any existing TestProf data to ensure fresh results
      return unless defined?(TestProf::FactoryProf)

      TestProf::FactoryProf.reset if TestProf::FactoryProf.respond_to?(:reset)
    end

    def execute_rspec_with_profiling(spec_location)
      # Build RSpec command
      rspec_command = build_rspec_command(spec_location)

      log_debug("Executing RSpec command: #{rspec_command}")

      # Execute RSpec and capture output
      success = system(rspec_command)

      raise TestProfError, "RSpec execution failed for #{spec_location || 'all specs'}" unless success

      @enabled = true
      log_debug('RSpec execution completed successfully')
    end

    def build_rspec_command(spec_location)
      command_parts = %w[bundle exec rspec]

      # Add spec location if provided
      command_parts << spec_location if spec_location && !spec_location.empty?

      # Add TestProf-specific options
      command_parts << '--format' << 'progress' # Use progress format to minimize output

      # Set environment variables for TestProf
      env_vars = {
        'FPROF' => '1', # Enable FactoryProf
        'FPROF_MODE' => 'simple' # Use simple mode for easier parsing
      }

      # Build final command with environment variables
      env_string = env_vars.map { |k, v| "#{k}=#{v}" }.join(' ')
      "#{env_string} #{command_parts.join(' ')}"
    end

    def log_debug(message)
      return unless ENV['SPEC_SCOUT_DEBUG'] == 'true'

      puts "[DEBUG] TestProfIntegration: #{message}"
    end

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

      # Try to get FactoryProf results from different sources
      factory_data = {}

      # Method 1: Try to get stats directly
      if TestProf::FactoryProf.respond_to?(:stats) && TestProf::FactoryProf.stats
        stats = TestProf::FactoryProf.stats
        factory_data = extract_factory_stats_from_hash(stats) if stats.is_a?(Hash)
      end

      # Method 2: Try to get data from FactoryProf instance
      if factory_data.empty? && defined?(TestProf::FactoryProf::Printers)
        # FactoryProf might store data in printers or other locations
        # This is a fallback approach
      end

      # Method 3: Parse from TestProf output files if available
      factory_data = parse_factory_prof_from_files if factory_data.empty?

      {
        total_count: factory_data.values.sum { |s| s[:count] || 0 },
        total_time: factory_data.values.sum { |s| s[:time] || 0.0 },
        stats: factory_data
      }
    rescue StandardError => e
      # Log error but don't fail the entire extraction
      log_debug("FactoryProf extraction failed: #{e.message}")
      { error: "FactoryProf extraction failed: #{e.message}" }
    end

    def extract_factory_stats_from_hash(stats)
      return {} unless stats.is_a?(Hash)

      result = {}
      stats.each do |factory_name, factory_data|
        # Handle different TestProf data formats
        if factory_data.is_a?(Hash)
          result[factory_name.to_sym] = {
            count: factory_data[:total] || factory_data[:count] || 0,
            time: factory_data[:time] || 0.0,
            strategy: detect_factory_strategy(factory_data)
          }
        elsif factory_data.is_a?(Numeric)
          # Simple count format
          result[factory_name.to_sym] = {
            count: factory_data,
            time: 0.0,
            strategy: :create # Default assumption
          }
        end
      end
      result
    rescue StandardError => e
      log_debug("Factory stats extraction failed: #{e.message}")
      {}
    end

    def parse_factory_prof_from_files
      # Try to parse FactoryProf output from tmp/test_prof directory
      factory_data = {}

      output_dir = 'tmp/test_prof'
      return factory_data unless Dir.exist?(output_dir)

      # Look for FactoryProf output files
      factory_files = Dir.glob(File.join(output_dir, '*factory*'))

      factory_files.each do |file|
        content = File.read(file)
        parsed_data = parse_factory_prof_content(content)
        factory_data.merge!(parsed_data) if parsed_data.any?
      rescue StandardError => e
        log_debug("Failed to parse factory file #{file}: #{e.message}")
      end

      factory_data
    end

    def parse_factory_prof_content(content)
      # Parse FactoryProf text output
      # This is a simplified parser - real implementation would need more robust parsing
      factory_data = {}

      # Look for lines like: "user (3) - 0.123s"
      content.scan(/(\w+)\s*\((\d+)\)\s*-\s*([\d.]+)s?/) do |name, count, time|
        factory_data[name.to_sym] = {
          count: count.to_i,
          time: time.to_f,
          strategy: :create # Default assumption
        }
      end

      factory_data
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
