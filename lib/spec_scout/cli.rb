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

      # Parse configuration from CLI args
      config = parse_args(args)

      # Create and run SpecScout
      scout = SpecScout.new(config)
      result = scout.analyze

      # Handle output
      handle_output(result, config)

      # Exit with appropriate code for CI/enforcement mode
      exit_code = determine_exit_code(result, config)
      exit(exit_code) if exit_code > 0

      result
    rescue StandardError => e
      handle_cli_error(e)
      exit(1)
    end

    def self.parse_args(args)
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
        # Store spec location in config metadata for now
        # This could be enhanced later if needed

        when /^--/
          raise ArgumentError, "Unknown option: #{args[i]}"
        end
        i += 1
      end

      config.validate!
      config
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
          spec_scout spec/models/user_spec.rb  # Analyze specific spec file

        Environment Variables:
          SPEC_SCOUT_DEBUG=1          Enable debug output
      HELP
    end
  end
end
