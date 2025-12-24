# frozen_string_literal: true

module SpecScout
  # Configuration class for Spec Scout settings
  class Configuration
    attr_accessor :enable, :use_test_prof, :fail_on_high_confidence,
                  :enabled_agents, :output_format, :enforcement_mode

    VALID_OUTPUT_FORMATS = %i[console json].freeze
    VALID_AGENTS = %i[database factory intent risk].freeze

    def initialize
      @enable = true
      @use_test_prof = true
      @fail_on_high_confidence = false
      @enabled_agents = VALID_AGENTS.dup
      @output_format = :console
      @enforcement_mode = false
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
        enforcement_mode: @enforcement_mode
      }
    end
  end
end
