# frozen_string_literal: true

module SpecScout
  # Converts TestProf output formats to ProfileData schema
  class ProfileNormalizer
    class NormalizationError < StandardError; end

    def initialize
      @current_example_location = nil
    end

    # Convert TestProf output to normalized ProfileData
    def normalize(testprof_data, example_context = {})
      validate_input(testprof_data)

      ProfileData.new(
        example_location: extract_example_location(example_context),
        spec_type: infer_spec_type(example_context),
        runtime_ms: extract_runtime(testprof_data, example_context),
        factories: normalize_factory_data(testprof_data),
        db: normalize_db_data(testprof_data),
        events: normalize_event_data(testprof_data),
        metadata: extract_metadata(testprof_data, example_context)
      )
    rescue StandardError => e
      raise NormalizationError, "Failed to normalize TestProf data: #{e.message}"
    end

    # Set current example context for normalization
    def set_example_context(location)
      @current_example_location = location
    end

    private

    def validate_input(testprof_data)
      return if testprof_data.is_a?(Hash)

      raise NormalizationError, "TestProf data must be a Hash, got #{testprof_data.class}"
    end

    def extract_example_location(example_context)
      # Try multiple sources for example location
      location = example_context[:location] ||
                 example_context[:file_path] ||
                 @current_example_location ||
                 ''

      # Ensure location is a string
      location.to_s
    end

    def infer_spec_type(example_context)
      location = extract_example_location(example_context)

      case location
      when %r{spec/models/}
        :model
      when %r{spec/controllers/}
        :controller
      when %r{spec/requests/}
        :request
      when %r{spec/features/}
        :feature
      when %r{spec/integration/}
        :integration
      when %r{spec/system/}
        :system
      when %r{spec/lib/}
        :lib
      when %r{spec/helpers/}
        :helper
      when %r{spec/views/}
        :view
      else
        :unknown
      end
    end

    def extract_runtime(testprof_data, example_context)
      # Try to extract runtime from various sources
      runtime = example_context[:runtime] ||
                example_context[:duration] ||
                testprof_data.dig(:metadata, :runtime) ||
                0

      # Convert to milliseconds if needed
      case runtime
      when Numeric
        runtime < 1 ? (runtime * 1000).round(2) : runtime.round(2)
      else
        0
      end
    end

    def normalize_factory_data(testprof_data)
      factory_data = testprof_data[:factory_prof] || {}
      return {} if factory_data.empty?

      normalized = {}

      # Handle FactoryProf stats format
      factory_data[:stats]&.each do |factory_name, stats|
        normalized[factory_name] = {
          strategy: stats[:strategy] || :unknown,
          count: stats[:count] || 0,
          time: stats[:time] || 0.0
        }
      end

      # Handle alternative factory data formats
      factory_data[:factories]&.each do |factory_name, factory_info|
        normalized[factory_name] = normalize_single_factory(factory_info)
      end

      normalized
    end

    def normalize_single_factory(factory_info)
      case factory_info
      when Hash
        {
          strategy: factory_info[:strategy] || detect_strategy_from_info(factory_info),
          count: factory_info[:count] || factory_info[:total] || 1,
          time: factory_info[:time] || factory_info[:duration] || 0.0
        }
      when Numeric
        {
          strategy: :unknown,
          count: factory_info,
          time: 0.0
        }
      else
        {
          strategy: :unknown,
          count: 1,
          time: 0.0
        }
      end
    end

    def detect_strategy_from_info(factory_info)
      # Try to detect strategy from various indicators
      if factory_info[:create_count]&.positive?
        :create
      elsif factory_info[:build_count]&.positive?
        :build
      elsif factory_info[:build_stubbed_count]&.positive?
        :build_stubbed
      elsif factory_info[:method]
        factory_info[:method].to_sym
      else
        :unknown
      end
    end

    def normalize_db_data(testprof_data)
      db_data = testprof_data[:db_queries] || {}

      # Provide default structure
      normalized = {
        total_queries: 0,
        inserts: 0,
        selects: 0,
        updates: 0,
        deletes: 0
      }

      # Merge with actual data if available
      normalized.merge!(db_data.slice(:total_queries, :inserts, :selects, :updates, :deletes)) if db_data.is_a?(Hash)

      # Ensure all values are numeric
      normalized.transform_values { |v| v.is_a?(Numeric) ? v : 0 }
    end

    def normalize_event_data(testprof_data)
      event_data = testprof_data[:event_prof] || {}
      return {} unless event_data[:events]

      normalized = {}

      event_data[:events].each do |event_name, event_info|
        normalized[event_name] = {
          count: event_info[:count] || 0,
          time: event_info[:time] || 0.0,
          examples: normalize_event_examples(event_info[:examples])
        }
      end

      normalized
    end

    def normalize_event_examples(examples)
      return [] unless examples.is_a?(Array)

      examples.map do |example|
        case example
        when Hash
          example.slice(:sql, :time, :location, :backtrace)
        when String
          { sql: example }
        else
          {}
        end
      end.compact
    end

    def extract_metadata(testprof_data, example_context)
      metadata = {}

      # Add TestProf metadata
      metadata.merge!(testprof_data[:metadata]) if testprof_data[:metadata]

      # Add example context metadata
      metadata[:example_group] = example_context[:example_group] if example_context[:example_group]
      metadata[:tags] = example_context[:tags] if example_context[:tags]
      metadata[:description] = example_context[:description] if example_context[:description]

      # Add normalization timestamp
      metadata[:normalized_at] = Time.now.strftime('%Y-%m-%dT%H:%M:%S%z')

      # Add any error information
      if testprof_data[:factory_prof] && testprof_data[:factory_prof][:error]
        metadata[:factory_prof_error] = testprof_data[:factory_prof][:error]
      end

      if testprof_data[:event_prof] && testprof_data[:event_prof][:error]
        metadata[:event_prof_error] = testprof_data[:event_prof][:error]
      end

      if testprof_data[:db_queries] && testprof_data[:db_queries][:error]
        metadata[:db_queries_error] = testprof_data[:db_queries][:error]
      end

      metadata
    end
  end
end
