# frozen_string_literal: true

require_relative 'llm_optimizer_manager'
require_relative 'optimizer_result'

module SpecScout
  # Main orchestration class that coordinates TestProf integration, agents, and consensus
  class SpecScout
    attr_reader :config, :safety_validator, :enforcement_handler, :ai_agent_manager

    def initialize(config = nil)
      @config = config || ::SpecScout.configuration
      @config.validate!
      @safety_validator = SafetyValidator.new(@config)
      @enforcement_handler = EnforcementHandler.new(@config)
      @ai_agent_manager = LlmOptimizerManager.new(@config)
    end

    # Main entry point for both CLI and programmatic execution
    def analyze(spec_location = nil)
      log_debug("Starting SpecScout analysis for: #{spec_location || 'all specs'}")

      return disabled_result unless @config.enabled?

      begin
        # Validate enforcement configuration
        log_debug('Validating enforcement configuration')
        @enforcement_handler.validate_enforcement_config!

        # Perform safety validations before analysis
        log_debug('Performing safety validations')
        perform_safety_validations(spec_location)

        # Execute TestProf profiling if enabled
        log_debug('Executing TestProf profiling')
        profile_data = execute_profiling(spec_location)
        return no_profile_data_result unless profile_data

        # Run agent analysis
        log_debug('Running agent analysis')
        agent_results = run_agents(profile_data)

        # Check if we have any successful agent results
        successful_results = agent_results.reject { |result| result.verdict == :optimizer_failed }
        return no_agents_result if successful_results.empty?

        # Generate consensus recommendation
        log_debug('Generating consensus recommendation')
        recommendation = generate_recommendation(agent_results, profile_data)

        # Validate no mutations occurred during analysis
        log_debug('Validating no mutations occurred')
        @safety_validator.validate_no_mutations!

        # Handle enforcement mode
        log_debug('Handling enforcement mode')
        enforcement_result = @enforcement_handler.handle_enforcement(
          recommendation[:recommendation],
          profile_data
        )

        final_result = recommendation.merge(enforcement_result)
        log_debug('SpecScout analysis completed successfully')
        final_result
      rescue SafetyValidator::SafetyViolationError => e
        log_error("Safety violation detected: #{e.message}")
        handle_safety_violation(e)
      rescue EnforcementHandler::EnforcementFailureError => e
        log_error("Enforcement failure: #{e.message}")
        handle_enforcement_error(e)
      rescue StandardError => e
        log_error("Unexpected error during analysis: #{e.message}")
        log_debug("Full backtrace: #{e.backtrace.join("\n")}") if debug_enabled?
        handle_error(e)
      end
    end

    # CLI execution mode
    def self.run_cli(args = ARGV)
      begin
        config = parse_cli_args(args)
        scout = new(config)

        puts '🔍 SpecScout starting analysis...' if config.console_output? && config.debug_mode?

        result = scout.analyze

        # Output results
        if result[:recommendation] && result[:profile_data]
          formatter = OutputFormatter.new(result[:recommendation], result[:profile_data])
          output = config.json_output? ? formatter.format_json : formatter.format_recommendation
          puts output
        elsif result[:disabled]
          puts 'SpecScout is disabled' if config.console_output?
        elsif result[:no_profile_data]
          puts 'No profile data available - ensure TestProf is properly configured' if config.console_output?
        elsif result[:no_agents]
          puts 'No agents produced results - check agent configuration' if config.console_output?
        elsif result[:error]
          puts "Analysis failed: #{result[:error].message}" if config.console_output?
        end

        # Handle enforcement mode output
        puts result[:enforcement_message] if result[:enforcement_message] && !config.json_output?

        # Handle safety violations
        puts "🚨 Safety violation: #{result[:safety_violation]}" if result[:safety_violation] && !config.json_output?

        # Handle enforcement errors
        puts "⚠️ Enforcement error: #{result[:enforcement_error]}" if result[:enforcement_error] && !config.json_output?

        # Exit with appropriate code for CI
        exit_code = result[:exit_code] || (result[:should_fail] ? 1 : 0)

        puts "🏁 SpecScout completed with exit code: #{exit_code}" if config.console_output? && config.debug_mode?
        exit(exit_code)
      rescue StandardError => e
        warn "🚨 SpecScout CLI failed: #{e.message}"
        warn "Backtrace: #{e.backtrace.join("\n")}" if ENV['SPEC_SCOUT_DEBUG']
        exit(1)
      end

      result
    end

    # Programmatic execution mode
    def self.analyze_spec(spec_location = nil, config = nil)
      scout = new(config)
      scout.analyze(spec_location)
    end

    private

    def perform_safety_validations(spec_location)
      # Prevent auto-application of code changes by default
      @safety_validator.prevent_auto_application!

      # Validate non-blocking operation mode
      @safety_validator.validate_non_blocking_mode!

      # Monitor spec files to detect mutations
      spec_paths = collect_spec_paths(spec_location)
      @safety_validator.monitor_spec_files(spec_paths)
    end

    def collect_spec_paths(spec_location)
      return [] unless spec_location

      if File.directory?(spec_location)
        Dir.glob(File.join(spec_location, '**', '*_spec.rb'))
      elsif File.file?(spec_location)
        [spec_location]
      else
        # Try to find spec files in common locations
        spec_dirs = %w[spec test]
        spec_files = []

        spec_dirs.each do |dir|
          next unless Dir.exist?(dir)

          spec_files.concat(Dir.glob(File.join(dir, '**', '*_spec.rb')))
          spec_files.concat(Dir.glob(File.join(dir, '**', '*_test.rb')))
        end

        spec_files
      end
    end

    def handle_safety_violation(error)
      warn "🚨 Safety Violation: #{error.message}" if @config.console_output?

      {
        recommendation: nil,
        profile_data: nil,
        agent_results: [],
        safety_violation: error.message,
        should_fail: true, # Safety violations should always fail
        exit_code: 1
      }
    end

    def handle_enforcement_error(error)
      warn "⚠️ Enforcement Error: #{error.message}" if @config.console_output?

      {
        recommendation: error.recommendation,
        profile_data: nil,
        agent_results: [],
        enforcement_error: error.message,
        should_fail: true,
        exit_code: 1
      }
    end

    def execute_profiling(spec_location)
      return nil unless @config.test_prof_enabled?

      log_debug("Starting TestProf integration for: #{spec_location || 'all specs'}")

      integration = TestProfIntegration.new(@config)
      profile_data = integration.execute_profiling(spec_location)

      if profile_data.nil? || profile_data.empty?
        log_debug('No profile data returned from TestProf integration')
        return nil
      end

      log_debug("TestProf data extracted successfully: #{profile_data.keys}")

      normalizer = ProfileNormalizer.new
      normalized_data = normalizer.normalize(profile_data, build_example_context(spec_location))

      log_debug('Profile data normalized successfully')
      normalized_data
    rescue TestProfIntegration::TestProfError => e
      log_error("TestProf integration failed: #{e.message}")
      nil
    rescue ProfileNormalizer::NormalizationError => e
      log_error("Profile data normalization failed: #{e.message}")
      nil
    rescue StandardError => e
      log_error("Unexpected error during profiling: #{e.message}")
      log_debug("Backtrace: #{e.backtrace.join("\n")}") if debug_enabled?
      nil
    end

    def run_agents(profile_data)
      log_debug("Starting agent analysis with #{@config.enabled_agents.size} enabled agents")
      log_debug("Agent execution mode: #{@config.agent_execution_mode}")

      # Validate profile data before running agents
      unless profile_data.is_a?(ProfileData) && profile_data.valid?
        log_error('Invalid profile data provided to agents')
        return []
      end

      case @config.agent_execution_mode
      when :ai_only
        run_ai_agents_only(profile_data)
      when :hybrid
        run_hybrid_agents(profile_data)
      when :rule_based_only
        run_rule_based_agents(profile_data)
      else
        log_error("Unknown agent execution mode: #{@config.agent_execution_mode}")
        run_rule_based_agents(profile_data) # Safe fallback
      end
    rescue StandardError => e
      log_error("Agent execution failed: #{e.message}")
      log_debug("Agent execution backtrace: #{e.backtrace.join("\n")}") if debug_enabled?

      # Return empty results on complete failure
      []
    end

    def run_ai_agents_only(profile_data)
      log_debug('Running AI agents only')

      unless @ai_agent_manager.llm_optimizers_available?
        log_error('AI agents not available but AI-only mode requested')
        return []
      end

      begin
        spec_content = load_spec_content_for_ai(profile_data)
        agent_results = @ai_agent_manager.run_optimizers(profile_data, spec_content)

        if agent_results.any?
          log_debug("AI-only agent analysis completed: #{agent_results.size} results")

          # Validate AI agent results
          validated_results = validate_and_filter_agent_results(agent_results, :ai_only)
          log_debug("AI-only validated results: #{validated_results.size}")

          validated_results
        else
          log_error('No AI agent results in AI-only mode')
          []
        end
      rescue StandardError => e
        log_error("AI-only agent execution failed: #{e.message}")
        log_debug("AI-only agent backtrace: #{e.backtrace.join("\n")}") if debug_enabled?

        # In AI-only mode, we don't fallback - return empty results
        []
      end
    end

    def run_hybrid_agents(profile_data)
      log_debug('Running hybrid agents (AI + rule-based)')
      all_results = []

      # First, try AI agents
      if @ai_agent_manager.llm_optimizers_available?
        log_debug('Running AI agents in hybrid mode')

        begin
          spec_content = load_spec_content_for_ai(profile_data)
          ai_results = @ai_agent_manager.run_optimizers(profile_data, spec_content)

          if ai_results.any?
            log_debug("AI agents completed in hybrid mode: #{ai_results.size} results")

            # Validate AI results and mark them as AI-generated
            validated_ai_results = validate_and_filter_agent_results(ai_results, :hybrid_ai)
            validated_ai_results.each { |result| result.metadata[:execution_mode] = :ai }

            all_results.concat(validated_ai_results)
          else
            log_debug('No AI agent results in hybrid mode')
          end
        rescue StandardError => e
          log_error("AI agents failed in hybrid mode: #{e.message}")
          log_debug("AI agent backtrace: #{e.backtrace.join("\n")}") if debug_enabled?
        end
      else
        log_debug('AI agents not available in hybrid mode')
      end

      # Then, run rule-based agents for any missing agent types
      rule_based_results = run_rule_based_agents_selective(profile_data, all_results)
      all_results.concat(rule_based_results)

      log_debug("Hybrid agent analysis completed: #{all_results.size} total results")

      # Final validation of all results
      validate_and_filter_agent_results(all_results, :hybrid_final)
    end

    def run_rule_based_agents_selective(profile_data, existing_results)
      log_debug('Running selective rule-based agents')

      # Determine which agent types we already have results for
      existing_agent_types = existing_results.map do |result|
        result.respond_to?(:optimizer_name) ? result.optimizer_name : result.agent_name
      end.uniq
      missing_agent_types = @config.enabled_agents - existing_agent_types

      log_debug("Missing agent types for rule-based fallback: #{missing_agent_types}")

      agent_results = []

      missing_agent_types.each do |agent_name|
        next unless @config.agent_enabled?(agent_name)

        log_debug("Running rule-based #{agent_name} agent")

        begin
          agent = create_agent(agent_name, profile_data)
          result = agent.evaluate

          # Validate agent result structure
          validate_agent_result(result, agent_name)

          # Convert to AgentResult if needed and mark as rule-based
          agent_result = ensure_agent_result(result, agent_name)
          agent_result.metadata[:execution_mode] = :rule_based
          agent_result.metadata[:hybrid_fallback] = true

          agent_results << agent_result
          log_debug("Rule-based #{agent_name} agent completed: #{result[:verdict]} (#{result[:confidence]})")
        rescue StandardError => e
          log_error("Rule-based agent #{agent_name} failed: #{e.message}")
          log_debug("Rule-based agent #{agent_name} backtrace: #{e.backtrace.join("\n")}") if debug_enabled?

          # Create a failed agent result for debugging
          failed_result = create_failed_agent_result(agent_name, e.message)
          failed_result.metadata[:execution_mode] = :rule_based
          failed_result.metadata[:hybrid_fallback] = true

          # Only include failed results in debug mode
          agent_results << failed_result if debug_enabled?
        end
      end

      agent_results
    end

    def run_rule_based_agents(profile_data)
      log_debug('Running rule-based agents')
      agent_results = []

      # Run each enabled agent
      @config.enabled_agents.each do |agent_name|
        next unless @config.agent_enabled?(agent_name)

        log_debug("Running rule-based #{agent_name} agent")

        begin
          agent = create_agent(agent_name, profile_data)
          result = agent.evaluate

          # Validate agent result structure
          validate_agent_result(result, agent_name)

          # Convert to AgentResult if needed and mark as rule-based
          agent_result = ensure_agent_result(result, agent_name)
          agent_result.metadata[:execution_mode] = :rule_based

          agent_results << agent_result
          log_debug("Rule-based #{agent_name} agent completed: #{result[:verdict]} (#{result[:confidence]})")
        rescue StandardError => e
          log_error("Rule-based agent #{agent_name} failed: #{e.message}")
          log_debug("Rule-based agent #{agent_name} backtrace: #{e.backtrace.join("\n")}") if debug_enabled?

          # Create a failed agent result for debugging
          failed_result = create_failed_agent_result(agent_name, e.message)
          failed_result.metadata[:execution_mode] = :rule_based

          # Only include failed results in debug mode
          agent_results << failed_result if debug_enabled?
        end
      end

      log_debug("Rule-based agent analysis completed: #{agent_results.size} successful results")

      # Final validation of rule-based results
      validate_and_filter_agent_results(agent_results, :rule_based_only)
    end

    # Validate and filter agent results to ensure quality
    def validate_and_filter_agent_results(agent_results, context)
      return [] if agent_results.empty?

      validated_results = []

      agent_results.each do |result|
        # Ensure result is an OptimizerResult object
        optimizer_name = if result.respond_to?(:optimizer_name)
                           result.optimizer_name
                         elsif result.respond_to?(:agent_name)
                           result.agent_name
                         else
                           :unknown
                         end
        validated_result = ensure_agent_result(result, optimizer_name)

        # Validate the result structure
        if validated_result.valid?
          validated_results << validated_result
          log_debug("#{context}: Validated result from #{validated_result.optimizer_name}")
        else
          log_error("#{context}: Invalid result from #{validated_result.optimizer_name}")
        end
      rescue StandardError => e
        log_error("#{context}: Failed to validate result: #{e.message}")
      end

      log_debug("#{context}: #{validated_results.size}/#{agent_results.size} results validated")
      validated_results
    end

    # Load spec content for AI agents
    def load_spec_content_for_ai(profile_data)
      return nil unless profile_data.respond_to?(:example_location)
      return nil unless profile_data.example_location

      spec_location = profile_data.example_location.split(':').first # Remove line number
      return nil unless File.exist?(spec_location)

      File.read(spec_location)
    rescue StandardError => e
      log_debug("Failed to load spec content: #{e.message}")
      nil
    end

    # Ensure result is an OptimizerResult object
    def ensure_agent_result(result, agent_name)
      if result.is_a?(OptimizerResult)
        result
      elsif result.is_a?(AgentResult)
        # Convert AgentResult to OptimizerResult for consistency
        OptimizerResult.new(
          optimizer_name: result.respond_to?(:agent_name) ? result.agent_name : agent_name,
          verdict: result.verdict,
          confidence: result.confidence,
          reasoning: result.reasoning,
          metadata: result.metadata || {}
        )
      else
        # Convert Hash to OptimizerResult for consistency
        OptimizerResult.new(
          optimizer_name: agent_name,
          verdict: result[:verdict],
          confidence: result[:confidence],
          reasoning: result[:reasoning],
          metadata: result[:metadata] || {}
        )
      end
    end

    # Create a failed optimizer result
    def create_failed_agent_result(agent_name, error_message)
      OptimizerResult.new(
        optimizer_name: agent_name,
        verdict: :optimizer_failed,
        confidence: :low,
        reasoning: "Optimizer execution failed: #{error_message}",
        metadata: { error: error_message, failed_at: Time.now }
      )
    end

    def create_agent(agent_name, profile_data)
      case agent_name
      when :database
        Optimizers::RuleBased::DatabaseOptimiser.new(profile_data)
      when :factory
        Optimizers::RuleBased::FactoryOptimiser.new(profile_data)
      when :intent
        Optimizers::RuleBased::IntentOptimiser.new(profile_data)
      when :risk
        Optimizers::RuleBased::RiskOptimiser.new(profile_data)
      else
        raise ArgumentError, "Unknown agent: #{agent_name}"
      end
    end

    def generate_recommendation(agent_results, profile_data)
      log_debug("Generating consensus from #{agent_results.size} agent results")

      # Filter out failed agent results for consensus
      successful_results = agent_results.reject { |result| result.verdict == :optimizer_failed }

      if successful_results.empty?
        log_error('No successful agent results for consensus generation')
        return create_no_agents_recommendation(profile_data, agent_results)
      end

      begin
        consensus = ConsensusEngine.new(successful_results, profile_data)
        recommendation = consensus.generate_recommendation

        # Add AI integration metadata to recommendation
        add_ai_integration_metadata(recommendation, agent_results)

        log_debug("Consensus generated: #{recommendation.action} (#{recommendation.confidence})")

        {
          recommendation: recommendation,
          profile_data: profile_data,
          agent_results: agent_results # Include all results (including failed ones) for debugging
        }
      rescue StandardError => e
        log_error("Consensus generation failed: #{e.message}")
        log_debug("Consensus backtrace: #{e.backtrace.join("\n")}") if debug_enabled?

        # Return a fallback result
        {
          recommendation: create_fallback_recommendation(e, profile_data),
          profile_data: profile_data,
          agent_results: agent_results
        }
      end
    end

    # Add AI integration metadata to recommendation
    def add_ai_integration_metadata(recommendation, agent_results)
      return unless recommendation.metadata.is_a?(Hash)

      ai_results = agent_results.select { |r| r.metadata[:execution_mode] == :ai }
      rule_based_results = agent_results.select { |r| r.metadata[:execution_mode] == :rule_based }
      failed_results = agent_results.select { |r| r.verdict == :optimizer_failed }

      recommendation.metadata[:ai_integration] = {
        total_agents: agent_results.size,
        ai_agents: ai_results.size,
        rule_based_agents: rule_based_results.size,
        failed_agents: failed_results.size,
        execution_mode: @config.agent_execution_mode,
        ai_available: @ai_agent_manager.llm_optimizers_available?,
        fallback_occurred: agent_results.any? { |r| r.metadata[:fallback] }
      }

      # Add LLM provider information if AI agents were used
      return unless ai_results.any?

      llm_providers = ai_results.map { |r| r.metadata[:llm_provider] }.compact.uniq
      recommendation.metadata[:ai_integration][:llm_providers] = llm_providers
    end

    # Create recommendation when no agents succeed
    def create_no_agents_recommendation(profile_data, agent_results)
      failed_count = agent_results.count { |r| r.verdict == :optimizer_failed }

      {
        recommendation: Recommendation.new(
          spec_location: profile_data.example_location,
          action: :no_action,
          from_value: '',
          to_value: '',
          confidence: :none,
          explanation: [
            'No successful agent results available for analysis',
            "#{failed_count} agent(s) failed during execution",
            'Check configuration and try again'
          ],
          agent_results: agent_results,
          metadata: {
            no_successful_agents: true,
            failed_agent_count: failed_count,
            execution_mode: @config.agent_execution_mode
          }
        ),
        profile_data: profile_data,
        agent_results: agent_results
      }
    end

    def handle_error(error)
      error_message = "SpecScout analysis failed: #{error.message}"

      # Check if this is an AI agent failure
      if ai_agent_error?(error)
        error_message = "AI agent analysis failed: #{error.message}"
        log_error('AI agent failure detected, attempting fallback to rule-based agents')

        # If we have fallback enabled, don't treat this as a fatal error
        if @config.fallback_to_rule_based?
          log_debug('Fallback to rule-based agents is enabled')
          return attempt_rule_based_fallback(error)
        end
      end

      if @config.console_output?
        warn error_message
        warn "Error type: #{error.class.name}"

        if debug_enabled?
          warn 'Full backtrace:'
          warn error.backtrace.join("\n")
        else
          warn 'Run with SPEC_SCOUT_DEBUG=true for full backtrace'
        end
      end

      {
        recommendation: nil,
        profile_data: nil,
        agent_results: [],
        error: error,
        error_message: error_message,
        should_fail: ai_agent_error?(error) && !@config.fallback_to_rule_based?, # Fail if AI error and no fallback
        exit_code: ai_agent_error?(error) && !@config.fallback_to_rule_based? ? 1 : 0
      }
    end

    # Check if error is related to AI agent failure
    def ai_agent_error?(error)
      error.message.include?('AI agent') ||
        error.message.include?('LLM') ||
        error.message.include?('OpenAI') ||
        error.message.include?('Anthropic') ||
        error.is_a?(LlmOptimizerManager::LlmOptimizerError)
    rescue StandardError
      false
    end

    # Attempt fallback to rule-based agents when AI agents fail
    def attempt_rule_based_fallback(original_error)
      log_debug('Attempting rule-based fallback due to AI agent failure')

      begin
        # Try to get profile data if we don't have it
        profile_data = execute_profiling(nil) # Use nil for spec_location as fallback
        return no_profile_data_result unless profile_data

        # Run only rule-based agents
        agent_results = run_rule_based_agents(profile_data)
        return no_agents_result if agent_results.empty?

        # Generate consensus recommendation
        recommendation = generate_recommendation(agent_results, profile_data)

        # Add metadata about the fallback
        recommendation[:recommendation].metadata[:ai_fallback] = true
        recommendation[:recommendation].metadata[:original_ai_error] = original_error.message

        log_debug('Rule-based fallback completed successfully')
        recommendation
      rescue StandardError => e
        log_error("Rule-based fallback also failed: #{e.message}")

        {
          recommendation: nil,
          profile_data: nil,
          agent_results: [],
          error: original_error,
          fallback_error: e,
          error_message: 'Both AI agents and rule-based fallback failed',
          should_fail: true,
          exit_code: 1
        }
      end
    end

    def disabled_result
      {
        recommendation: nil,
        profile_data: nil,
        agent_results: [],
        disabled: true,
        should_fail: false,
        exit_code: 0
      }
    end

    def no_profile_data_result
      {
        recommendation: nil,
        profile_data: nil,
        agent_results: [],
        no_profile_data: true,
        should_fail: false,
        exit_code: 0
      }
    end

    def no_agents_result
      {
        recommendation: nil,
        profile_data: nil,
        agent_results: [],
        no_agents: true,
        should_fail: false,
        exit_code: 0
      }
    end

    # Parse CLI arguments into configuration
    def self.parse_cli_args(args)
      config = ::SpecScout.configuration.dup

      i = 0
      while i < args.length
        case args[i]
        when '--disable'
          config.enable = false
        when '--no-testprof'
          config.use_test_prof = false
        when '--enforce'
          config.enforcement_mode = true
        when '--fail-on-high-confidence'
          config.fail_on_high_confidence = true
        when '--auto-apply'
          config.auto_apply_enabled = true
        when '--blocking-mode'
          config.blocking_mode_enabled = true
        when '--output'
          i += 1
          config.output_format = args[i] if i < args.length
        when '--enable-agent'
          i += 1
          config.enable_agent(args[i]) if i < args.length
        when '--disable-agent'
          i += 1
          config.disable_agent(args[i]) if i < args.length
        when '--help', '-h'
          print_help
          exit(0)
        end
        i += 1
      end

      config.validate!
      config
    end

    def self.print_help
      puts <<~HELP
        SpecScout - Intelligent test optimization advisor

        Usage: spec_scout [options]

        Options:
          --disable                    Disable SpecScout analysis
          --no-testprof               Disable TestProf integration
          --enforce                   Enable enforcement mode (fail on high confidence)
          --fail-on-high-confidence   Fail on high confidence recommendations
          --auto-apply                Enable auto-application of code changes (UNSAFE)
          --blocking-mode             Enable blocking operation mode
          --output FORMAT             Output format (console, json)
          --enable-agent AGENT        Enable specific agent (database, factory, intent, risk)
          --disable-agent AGENT       Disable specific agent
          --help, -h                  Show this help message

        Safety Options:
          By default, SpecScout operates in safe mode:
          - No spec files are modified during analysis
          - No code changes are auto-applied
          - Non-blocking operation (recommendations only)

        Examples:
          spec_scout                           # Run with default settings (safe mode)
          spec_scout --enforce                 # Enable enforcement mode
          spec_scout --output json             # JSON output
          spec_scout --disable-agent risk      # Disable risk agent
          spec_scout --auto-apply --enforce    # UNSAFE: Enable auto-application
      HELP
    end

    # Build example context for profile normalization
    def build_example_context(spec_location)
      context = {}

      if spec_location
        context[:location] = spec_location
        context[:file_path] = spec_location
      end

      context
    end

    # Validate optimizer result structure
    def validate_agent_result(result, agent_name)
      # Handle both Hash and OptimizerResult objects
      case result
      when OptimizerResult
        # OptimizerResult objects are already validated
        true
      when AgentResult
        # AgentResult objects are already validated (for backward compatibility)
        true
      when Hash
        # Validate Hash format (for backward compatibility)
        required_keys = %i[verdict confidence reasoning]
        missing_keys = required_keys - result.keys

        unless missing_keys.empty?
          raise ArgumentError, "Agent #{agent_name} result missing required keys: #{missing_keys}"
        end

        # Validate confidence levels
        valid_confidence_levels = %i[high medium low none]
        unless valid_confidence_levels.include?(result[:confidence])
          raise ArgumentError, "Agent #{agent_name} returned invalid confidence level: #{result[:confidence]}"
        end
      else
        raise ArgumentError,
              "Agent #{agent_name} must return a Hash, AgentResult, or OptimizerResult, got #{result.class}"
      end
    end

    # Create fallback recommendation when consensus fails
    def create_fallback_recommendation(error, profile_data)
      Recommendation.new(
        spec_location: profile_data.example_location,
        action: :no_action,
        from_value: '',
        to_value: '',
        confidence: :none,
        explanation: [
          "Unable to generate recommendation due to consensus engine failure: #{error.message}",
          'This may indicate an issue with agent result processing',
          'Check logs for more details'
        ],
        agent_results: [],
        metadata: {
          consensus_failed: true,
          error_message: error.message,
          error_class: error.class.name
        }
      )
    end

    # Logging helpers
    def log_debug(message)
      return unless debug_enabled?

      return unless @config.console_output?

      puts "[DEBUG] SpecScout: #{message}"
    end

    def log_error(message)
      return unless @config.console_output?

      warn "[ERROR] SpecScout: #{message}"
    end

    def debug_enabled?
      ENV['SPEC_SCOUT_DEBUG'] == 'true' || @config.debug_mode?
    end
  end
end
