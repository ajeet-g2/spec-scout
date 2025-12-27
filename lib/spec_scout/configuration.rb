# frozen_string_literal: true

module SpecScout
  # Configuration class for Spec Scout settings
  # Supports enabling/disabling agents selectively, enforcement modes, and backward compatibility
  class Configuration
    attr_accessor :enable, :use_test_prof, :fail_on_high_confidence,
                  :enabled_agents, :output_format, :enforcement_mode,
                  :auto_apply_enabled, :blocking_mode_enabled

    VALID_OUTPUT_FORMATS = %i[console json].freeze
    VALID_AGENTS = %i[database factory intent risk].freeze

    def initialize
      @enable = true
      @use_test_prof = true
      @fail_on_high_confidence = false
      @enabled_agents = VALID_AGENTS.dup
      @output_format = :console
      @enforcement_mode = false
      @auto_apply_enabled = false # Safety: never auto-apply by default
      @blocking_mode_enabled = false # Safety: non-blocking by default
    end

    def enabled?
      @enable
    end

    def test_prof_enabled?
      @use_test_prof
    end

    def enforcement_mode?
      @enforcement_mode
    end

    def auto_apply_enabled?
      @auto_apply_enabled
    end

    def blocking_mode_enabled?
      @blocking_mode_enabled
    end

    def agent_enabled?(agent_name)
      @enabled_agents.include?(agent_name.to_sym)
    end

    def enable_agent(agent_name)
      agent_sym = agent_name.to_sym
      raise ArgumentError, "Unknown agent: #{agent_name}" unless VALID_AGENTS.include?(agent_sym)

      @enabled_agents << agent_sym unless @enabled_agents.include?(agent_sym)
    end

    def disable_agent(agent_name)
      @enabled_agents.delete(agent_name.to_sym)
    end

    def output_format=(format)
      format_sym = format.to_sym
      unless VALID_OUTPUT_FORMATS.include?(format_sym)
        raise ArgumentError, "Invalid output format: #{format}. Valid formats: #{VALID_OUTPUT_FORMATS}"
      end

      @output_format = format_sym
    end

    def json_output?
      @output_format == :json
    end

    def console_output?
      @output_format == :console
    end

    def debug_mode?
      ENV['SPEC_SCOUT_DEBUG'] == 'true'
    end

    def validate!
      unless @enabled_agents.all? { |agent| VALID_AGENTS.include?(agent) }
        invalid_agents = @enabled_agents - VALID_AGENTS
        raise ArgumentError, "Invalid agents: #{invalid_agents}. Valid agents: #{VALID_AGENTS}"
      end

      unless VALID_OUTPUT_FORMATS.include?(@output_format)
        raise ArgumentError, "Invalid output format: #{@output_format}. Valid formats: #{VALID_OUTPUT_FORMATS}"
      end

      true
    end

    def to_h
      {
        enable: @enable,
        use_test_prof: @use_test_prof,
        fail_on_high_confidence: @fail_on_high_confidence,
        enabled_agents: @enabled_agents,
        output_format: @output_format,
        enforcement_mode: @enforcement_mode,
        auto_apply_enabled: @auto_apply_enabled,
        blocking_mode_enabled: @blocking_mode_enabled
      }
    end

    # Create a duplicate configuration for CLI argument parsing
    def dup
      new_config = self.class.new
      new_config.enable = @enable
      new_config.use_test_prof = @use_test_prof
      new_config.fail_on_high_confidence = @fail_on_high_confidence
      new_config.enabled_agents = @enabled_agents.dup
      new_config.output_format = @output_format
      new_config.enforcement_mode = @enforcement_mode
      new_config.auto_apply_enabled = @auto_apply_enabled
      new_config.blocking_mode_enabled = @blocking_mode_enabled
      new_config
    end

    # Merge configuration from hash (for backward compatibility)
    def merge!(options = {})
      options.each do |key, value|
        case key.to_sym
        when :enable
          @enable = value
        when :use_test_prof
          @use_test_prof = value
        when :fail_on_high_confidence
          @fail_on_high_confidence = value
        when :enabled_agents
          @enabled_agents = Array(value).map(&:to_sym)
        when :output_format
          self.output_format = value
        when :enforcement_mode
          @enforcement_mode = value
        when :auto_apply_enabled
          @auto_apply_enabled = value
        when :blocking_mode_enabled
          @blocking_mode_enabled = value
        end
      end
      validate!
      self
    end

    # Check if enforcement should fail on high confidence
    def should_fail_on_high_confidence?
      @enforcement_mode && @fail_on_high_confidence
    end

    # Gracefully handle disabled TestProf integration
    def graceful_testprof_disable
      return self if @use_test_prof

      # When TestProf is disabled, we can still run agents on mock data
      # This maintains backward compatibility
      warn 'TestProf integration disabled - running in analysis-only mode' if @enable
      self
    end
  end
end
