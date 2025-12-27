# frozen_string_literal: true

module SpecScout
  # Main orchestration class that coordinates TestProf integration, agents, and consensus
  class SpecScout
    attr_reader :config, :safety_validator, :enforcement_handler

    def initialize(config = nil)
      @config = config || ::SpecScout.configuration
      @config.validate!
      @safety_validator = SafetyValidator.new(@config)
      @enforcement_handler = EnforcementHandler.new(@config)
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
        successful_results = agent_results.reject { |result| result.verdict == :agent_failed }
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
      agent_results = []

      # Run each enabled agent
      @config.enabled_agents.each do |agent_name|
        next unless @config.agent_enabled?(agent_name)

        log_debug("Running #{agent_name} agent")

        begin
          agent = create_agent(agent_name, profile_data)
          result = agent.evaluate

          # Validate agent result structure
          validate_agent_result(result, agent_name)

          # Handle both Hash and AgentResult objects
          if result.is_a?(AgentResult)
            agent_results << result
          else
            # Convert Hash to AgentResult for consistency
            agent_result = AgentResult.new(
              agent_name: agent_name,
              verdict: result[:verdict],
              confidence: result[:confidence],
              reasoning: result[:reasoning],
              metadata: result[:metadata] || {}
            )
            agent_results << agent_result
          end
          log_debug("#{agent_name} agent completed: #{result[:verdict]} (#{result[:confidence]})")
        rescue StandardError => e
          log_error("Agent #{agent_name} failed: #{e.message}")
          log_debug("Agent #{agent_name} backtrace: #{e.backtrace.join("\n")}") if debug_enabled?

          # Create a failed agent result for debugging
          failed_result = AgentResult.new(
            agent_name: agent_name,
            verdict: :agent_failed,
            confidence: :none,
            reasoning: "Agent execution failed: #{e.message}",
            metadata: { error: e.message, failed_at: Time.now }
          )

          # Only include failed results in debug mode
          agent_results << failed_result if debug_enabled?
        end
      end

      log_debug("Agent analysis completed: #{agent_results.size} successful results")
      agent_results
    end

    def create_agent(agent_name, profile_data)
      case agent_name
      when :database
        Agents::DatabaseAgent.new(profile_data)
      when :factory
        Agents::FactoryAgent.new(profile_data)
      when :intent
        Agents::IntentAgent.new(profile_data)
      when :risk
        Agents::RiskAgent.new(profile_data)
      else
        raise ArgumentError, "Unknown agent: #{agent_name}"
      end
    end

    def generate_recommendation(agent_results, profile_data)
      log_debug("Generating consensus from #{agent_results.size} agent results")

      begin
        consensus = ConsensusEngine.new(agent_results, profile_data)
        recommendation = consensus.generate_recommendation

        log_debug("Consensus generated: #{recommendation[:action]} (#{recommendation[:confidence]})")

        {
          recommendation: recommendation,
          profile_data: profile_data,
          agent_results: agent_results
        }
      rescue StandardError => e
        log_error("Consensus generation failed: #{e.message}")
        log_debug("Consensus backtrace: #{e.backtrace.join("\n")}") if debug_enabled?

        # Return a fallback result
        {
          recommendation: create_fallback_recommendation(e),
          profile_data: profile_data,
          agent_results: agent_results
        }
      end
    end

    def handle_error(error)
      error_message = "SpecScout analysis failed: #{error.message}"

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
        should_fail: false, # Don't fail by default on unexpected errors
        exit_code: 0
      }
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

    # Validate agent result structure
    def validate_agent_result(result, agent_name)
      # Handle both Hash and AgentResult objects
      if result.is_a?(AgentResult)
        # AgentResult objects are already validated
        true
      elsif result.is_a?(Hash)
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
        raise ArgumentError, "Agent #{agent_name} must return a Hash or AgentResult, got #{result.class}"
      end
    end

    # Create fallback recommendation when consensus fails
    def create_fallback_recommendation(error)
      Recommendation.new(
        spec_location: 'unknown',
        action: :no_action,
        from_value: nil,
        to_value: nil,
        confidence: :none,
        explanation: "Unable to generate recommendation due to consensus engine failure: #{error.message}",
        agent_results: []
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
