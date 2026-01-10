# frozen_string_literal: true

module SpecScout
  # Command Line Interface for SpecScout
  class CLI
    def self.run(args = ARGV)
      if args.include?('--version') || args.include?('-v')
        puts "SpecScout #{VERSION}"
        exit(0)
      end

      if args.include?('--help') || args.include?('-h')
        print_help
        exit(0)
      end

      # Parse configuration and spec file from CLI args
      config, spec_file = parse_args(args)

      # Create and run SpecScout
      scout = SpecScout.new(config)
      result = scout.analyze(spec_file)

      # Handle output
      handle_output(result, config)

      # Exit with appropriate code for CI/enforcement mode
      exit_code = determine_exit_code(result, config)
      exit(exit_code) if exit_code.positive?

      result
    rescue StandardError => e
      handle_cli_error(e)
      exit(1)
    end

    def self.parse_args(args)
      config = ::SpecScout.configuration.dup
      spec_file = nil

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
        when '--output', '-o'
          i += 1
          raise ArgumentError, '--output requires a format (console, json)' unless i < args.length

          config.output_format = args[i]

        when '--enable-agent'
          i += 1
          raise ArgumentError, '--enable-agent requires an agent name' unless i < args.length

          config.enable_agent(args[i])

        when '--disable-agent'
          i += 1
          raise ArgumentError, '--disable-agent requires an agent name' unless i < args.length

          config.disable_agent(args[i])

        when '--spec'
          i += 1
          raise ArgumentError, '--spec requires a spec file path' unless i < args.length

          spec_file = args[i]

        # LLM Provider selection
        when '--llm-provider'
          i += 1
          unless i < args.length
            raise ArgumentError,
                  '--llm-provider requires a provider (openai, anthropic, local_llm)'
          end

          config.llm_provider = args[i]

        # OpenAI configuration
        when '--openai-api-key'
          i += 1
          raise ArgumentError, '--openai-api-key requires an API key' unless i < args.length

          config.openai_config.api_key = args[i]

        when '--openai-model'
          i += 1
          raise ArgumentError, '--openai-model requires a model name' unless i < args.length

          config.openai_config.model = args[i]

        # Anthropic configuration
        when '--anthropic-api-key'
          i += 1
          raise ArgumentError, '--anthropic-api-key requires an API key' unless i < args.length

          config.anthropic_config.api_key = args[i]

        when '--anthropic-model'
          i += 1
          raise ArgumentError, '--anthropic-model requires a model name' unless i < args.length

          config.anthropic_config.model = args[i]

        # Local LLM configuration
        when '--local-llm-endpoint'
          i += 1
          raise ArgumentError, '--local-llm-endpoint requires an endpoint URL' unless i < args.length

          config.local_llm_config.endpoint = args[i]

        when '--local-llm-model'
          i += 1
          raise ArgumentError, '--local-llm-model requires a model name' unless i < args.length

          config.local_llm_config.model = args[i]

        # AI agent configuration
        when '--enable-ai-agents'
          config.enable_ai_agents

        when '--disable-ai-agents'
          config.disable_ai_agents

        when '--hybrid-mode'
          config.enable_hybrid_mode

        when '--ai-only'
          config.disable_hybrid_mode
          config.enable_ai_agents

        when '--rule-based-only'
          config.disable_ai_agents

        when '--ai-timeout'
          i += 1
          raise ArgumentError, '--ai-timeout requires a timeout in seconds' unless i < args.length

          timeout = args[i].to_i
          raise ArgumentError, '--ai-timeout must be a positive integer' unless timeout.positive?

          config.ai_agent_timeout = timeout

        when /^--/
          raise ArgumentError, "Unknown option: #{args[i]}"
        else
          # If it's not an option, treat it as a spec file path
          spec_file = args[i] if spec_file.nil?
        end
        i += 1
      end

      config.validate!
      [config, spec_file]
    end

    def self.handle_output(result, config)
      return unless result

      if result[:recommendation] && result[:profile_data]
        formatter = OutputFormatter.new(result[:recommendation], result[:profile_data])
        output = formatter.format_recommendation
        puts output
      elsif result[:disabled]
        puts 'SpecScout is disabled' if config.console_output?
      elsif result[:no_profile_data]
        puts 'No profile data available - ensure TestProf is properly configured' if config.console_output?
      elsif result[:no_agents]
        puts 'No agents produced results' if config.console_output?
      elsif result[:error]
        puts "Analysis failed: #{result[:error].message}" if config.console_output?
      end
    end

    def self.determine_exit_code(result, config)
      return 0 unless result
      return 0 unless config.enforcement_mode?
      return 0 unless result[:should_fail]

      1 # Fail in enforcement mode with high confidence recommendations
    end

    def self.handle_cli_error(error)
      case error
      when ArgumentError
        puts "Error: #{error.message}"
        puts 'Use --help for usage information'
      else
        puts "Unexpected error: #{error.message}"
        puts error.backtrace.join("\n") if ENV['SPEC_SCOUT_DEBUG']
      end
    end

    def self.print_help
      puts <<~HELP
        SpecScout - Intelligent test optimization advisor

        Usage: spec_scout [options] [spec_file]

        Options:
          --disable                    Disable SpecScout analysis
          --no-testprof               Disable TestProf integration
          --enforce                   Enable enforcement mode (fail on high confidence)
          --fail-on-high-confidence   Fail on high confidence recommendations
          --output FORMAT, -o FORMAT  Output format (console, json)
          --enable-agent AGENT        Enable specific agent (database, factory, intent, risk)
          --disable-agent AGENT       Disable specific agent
          --spec SPEC_FILE            Analyze specific spec file
          --version, -v               Show version
          --help, -h                  Show this help message

        LLM Provider Options:
          --llm-provider PROVIDER     LLM provider (openai, anthropic, local_llm)
          --openai-api-key KEY        OpenAI API key (or set OPENAI_API_KEY env var)
          --openai-model MODEL        OpenAI model (default: gpt-4)
          --anthropic-api-key KEY     Anthropic API key (or set ANTHROPIC_API_KEY env var)
          --anthropic-model MODEL     Anthropic model (default: claude-3-sonnet-20240229)
          --local-llm-endpoint URL    Local LLM endpoint (default: http://localhost:11434)
          --local-llm-model MODEL     Local LLM model (default: codellama)

        AI Agent Options:
          --enable-ai-agents          Enable AI-powered agents (default)
          --disable-ai-agents         Disable AI agents, use rule-based only
          --hybrid-mode               Use both AI and rule-based agents (default)
          --ai-only                   Use only AI agents
          --rule-based-only           Use only rule-based agents
          --ai-timeout SECONDS        AI agent timeout in seconds (default: 30)

        Agents:
          database    Analyze database usage patterns
          factory     Analyze FactoryBot strategy usage
          intent      Classify test intent and behavior
          risk        Identify potentially unsafe optimizations

        Examples:
          spec_scout                           # Run with default settings
          spec_scout --enforce                 # Enable enforcement mode
          spec_scout --output json             # JSON output
          spec_scout --disable-agent risk      # Disable risk agent
          spec_scout --llm-provider anthropic  # Use Anthropic Claude
          spec_scout --ai-only                 # Use only AI agents
          spec_scout --rule-based-only         # Use only rule-based agents
          spec_scout --openai-api-key sk-...   # Set OpenAI API key
          spec_scout spec/models/user_spec.rb  # Analyze specific spec file

        Environment Variables:
          SPEC_SCOUT_DEBUG=1          Enable debug output
          OPENAI_API_KEY              OpenAI API key
          ANTHROPIC_API_KEY           Anthropic API key
          LOCAL_LLM_ENDPOINT          Local LLM endpoint URL
          LOCAL_LLM_MODEL             Local LLM model name
      HELP
    end
  end
end
