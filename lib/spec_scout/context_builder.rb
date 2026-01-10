# frozen_string_literal: true

module SpecScout
  # Builds rich context for AI agents by combining profile data with
  # spec content, model analysis, and dependency information
  class ContextBuilder
    def initialize
      @file_cache = {}
    end

    # Build comprehensive context for AI agent analysis
    # @param profile_data [ProfileData] Normalized profiling data
    # @param spec_content [String, nil] Optional pre-loaded spec content
    # @param agent_type [Symbol] Type of agent (:database, :factory, :intent, :risk)
    # @return [Hash] Rich context hash for AI agent consumption
    def build_context(profile_data, spec_content = nil, agent_type = nil)
      base_context = build_base_context(profile_data, spec_content)

      # Add agent-specific context enhancements
      case agent_type
      when :risk
        base_context[:model_content] = load_model_content(profile_data)
        base_context[:callback_analysis] = analyze_model_callbacks(profile_data)
      when :intent
        base_context[:file_structure] = analyze_file_structure(profile_data.example_location)
        base_context[:test_dependencies] = analyze_test_dependencies(base_context[:spec_content])
      when :factory
        base_context[:factory_definitions] = load_factory_definitions(profile_data.factories.keys)
        base_context[:association_graph] = build_association_graph(profile_data)
      when :database
        base_context[:related_models] = extract_model_dependencies(base_context[:spec_content])
        base_context[:optimization_opportunities] = identify_optimization_patterns(profile_data)
      end

      base_context
    end

    private

    # Build the base context common to all agents
    def build_base_context(profile_data, spec_content)
      {
        spec_location: profile_data.example_location,
        spec_type: profile_data.spec_type,
        runtime_ms: profile_data.runtime_ms,
        factories: format_factories(profile_data.factories),
        database_usage: format_database_usage(profile_data.db),
        events: profile_data.events,
        spec_content: spec_content || load_spec_content(profile_data.example_location),
        metadata: profile_data.metadata
      }
    end

    # Load spec file content with caching
    def load_spec_content(spec_location)
      return nil unless spec_location && !spec_location.empty?
      return @file_cache[spec_location] if @file_cache.key?(spec_location)

      content = (File.read(spec_location) if File.exist?(spec_location))

      @file_cache[spec_location] = content
      content
    rescue StandardError => e
      warn "Failed to load spec content from #{spec_location}: #{e.message}"
      nil
    end

    # Load corresponding model file content for risk analysis
    def load_model_content(profile_data)
      model_path = extract_model_path(profile_data.example_location)
      return nil unless model_path

      load_file_with_cache(model_path)
    end

    # Extract model file path from spec location
    def extract_model_path(spec_location)
      return nil unless spec_location&.include?('spec/')

      # Remove line number if present and convert spec path to model path
      clean_location = spec_location.split(':').first

      # Convert spec path to model path
      # spec/models/user_spec.rb -> app/models/user.rb
      # spec/controllers/users_controller_spec.rb -> app/controllers/users_controller.rb
      clean_location
        .gsub(%r{^spec/}, 'app/')
        .gsub(/_spec\.rb$/, '.rb')

      # Return the path regardless of whether file exists (for testing purposes)
      # In real usage, we might want to check File.exist?(model_path)
    end

    # Load file content with caching
    def load_file_with_cache(file_path)
      return @file_cache[file_path] if @file_cache.key?(file_path)

      content = File.exist?(file_path) ? File.read(file_path) : nil
      @file_cache[file_path] = content
      content
    rescue StandardError => e
      warn "Failed to load file content from #{file_path}: #{e.message}"
      nil
    end

    # Analyze model callbacks for risk assessment
    def analyze_model_callbacks(profile_data)
      model_content = load_model_content(profile_data)
      return {} unless model_content

      callbacks = {}

      # Detect ActiveRecord callbacks
      callback_patterns = {
        after_commit: /after_commit\s+:(\w+)/,
        after_create: /after_create\s+:(\w+)/,
        after_update: /after_update\s+:(\w+)/,
        after_save: /after_save\s+:(\w+)/,
        before_validation: /before_validation\s+:(\w+)/
      }

      callback_patterns.each do |callback_type, pattern|
        matches = model_content.scan(pattern)
        callbacks[callback_type] = matches.flatten unless matches.empty?
      end

      callbacks
    end

    # Analyze file structure and location patterns
    def analyze_file_structure(spec_location)
      return {} unless spec_location

      # Remove line number from spec location for file analysis
      clean_location = spec_location.split(':').first

      {
        directory_depth: clean_location.split('/').length,
        spec_type_from_path: infer_spec_type_from_path(clean_location),
        is_nested: clean_location.include?('/') && clean_location.split('/').length > 2,
        file_name: File.basename(clean_location, '.rb')
      }
    end

    # Infer spec type from file path
    def infer_spec_type_from_path(spec_location)
      case spec_location
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
      else
        :unknown
      end
    end

    # Analyze test dependencies from spec content
    def analyze_test_dependencies(spec_content)
      return {} unless spec_content

      {
        requires_database: spec_content.match?(/create\(|save!|reload|find/),
        uses_external_services: spec_content.match?(/stub_request|WebMock|VCR/),
        has_file_operations: spec_content.match?(/File\.|Dir\.|Tempfile/),
        uses_time_travel: spec_content.match?(/travel_to|freeze_time|Timecop/),
        requires_javascript: spec_content.match?(/js:\s*true|javascript:\s*true/)
      }
    end

    # Load factory definitions for the given factory names
    def load_factory_definitions(factory_names)
      return {} unless factory_names&.any?

      definitions = {}
      factory_paths = find_factory_files

      factory_names.each do |factory_name|
        factory_paths.each do |path|
          content = load_file_with_cache(path)
          next unless content

          # Look for factory definition
          factory_match = content.match(/factory\s+:#{factory_name}.*?end/m)
          if factory_match
            definitions[factory_name] = factory_match[0]
            break
          end
        end
      end

      definitions
    end

    # Find factory files in the project
    def find_factory_files
      factory_paths = []

      # Common factory file locations
      %w[
        spec/factories.rb
        spec/factories/**/*.rb
        test/factories.rb
        test/factories/**/*.rb
      ].each do |pattern|
        factory_paths.concat(Dir.glob(pattern))
      end

      factory_paths.uniq
    end

    # Build association graph from profile data and factory usage
    def build_association_graph(profile_data)
      return {} unless profile_data.factories&.any?

      graph = {}

      profile_data.factories.each do |factory_name, factory_data|
        # Extract associations from factory definitions
        factory_def = load_factory_definitions([factory_name])[factory_name]
        next unless factory_def

        associations = extract_associations_from_factory(factory_def)
        graph[factory_name] = {
          strategy: factory_data[:strategy],
          count: factory_data[:count],
          associations: associations
        }
      end

      graph
    end

    # Extract associations from factory definition
    def extract_associations_from_factory(factory_definition)
      associations = []

      # Look for association patterns in factory definition
      association_patterns = [
        /association\s+:(\w+)/,
        /(\w+)\s+{\s*create\(/,
        /(\w+)\s+{\s*build\(/
      ]

      association_patterns.each do |pattern|
        matches = factory_definition.scan(pattern)
        associations.concat(matches.flatten) unless matches.empty?
      end

      associations.uniq
    end

    # Extract model dependencies from spec content
    def extract_model_dependencies(spec_content)
      return [] unless spec_content

      dependencies = []

      # Look for model class references
      model_patterns = [
        /([A-Z]\w+)\.create/,
        /([A-Z]\w+)\.find/,
        /([A-Z]\w+)\.where/,
        /([A-Z]\w+)\.new/,
        /create\(:(\w+)\)/,
        /build\(:(\w+)\)/
      ]

      model_patterns.each do |pattern|
        matches = spec_content.scan(pattern)
        dependencies.concat(matches.flatten) unless matches.empty?
      end

      dependencies.uniq.map(&:downcase)
    end

    # Identify optimization patterns from profile data
    def identify_optimization_patterns(profile_data)
      patterns = []

      # Database optimization patterns
      patterns << 'read_only_test' if profile_data.db[:inserts]&.zero? && profile_data.db[:selects]&.positive?

      patterns << 'high_query_count' if profile_data.db[:total_queries]&.> 10

      # Factory optimization patterns
      profile_data.factories.each_value do |data|
        patterns << 'bulk_factory_creation' if data[:strategy] == :create && data[:count] > 1
      end

      patterns
    end

    # Format factories for display
    def format_factories(factories)
      return 'No factories used' if factories.empty?

      factories.map do |name, data|
        "#{name}: #{data[:strategy]} (#{data[:count]}x)"
      end.join(', ')
    end

    # Format database usage for display
    def format_database_usage(db_data)
      return 'No database usage' if db_data.empty?

      parts = []
      parts << "Total queries: #{db_data[:total_queries]}" if db_data[:total_queries]
      parts << "Inserts: #{db_data[:inserts]}" if db_data[:inserts]
      parts << "Selects: #{db_data[:selects]}" if db_data[:selects]

      parts.join(', ')
    end
  end
end
