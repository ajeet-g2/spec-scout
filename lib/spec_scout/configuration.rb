# frozen_string_literal: true

require_relative 'llm_providers'
require_relative 'optimizer_registry'

module SpecScout
  # Configuration class for Spec Scout settings
  # Supports enabling/disabling agents selectively, enforcement modes, and backward compatibility
  class Configuration
    attr_accessor :enable, :use_test_prof, :fail_on_high_confidence,
                  :enabled_agents, :output_format, :enforcement_mode,
                  :auto_apply_enabled, :blocking_mode_enabled,
                  :llm_provider, :openai_config, :anthropic_config, :local_llm_config,
                  :agent_registry, :ai_agents_enabled, :hybrid_mode_enabled,
                  :fallback_to_rule_based, :ai_agent_timeout,
                  :file_editing_enabled, :backup_directory, :auto_rollback_on_error,
                  :max_changes_per_run, :require_confirmation, :dry_run_mode

    VALID_OUTPUT_FORMATS = %i[console json].freeze
    DEFAULT_AGENTS = %i[database factory intent risk].freeze
    VALID_LLM_PROVIDERS = %i[openai anthropic local_llm].freeze

    def initialize(agent_registry = nil)
      @enable = true
      @use_test_prof = true
      @fail_on_high_confidence = false
      @enabled_agents = DEFAULT_AGENTS.dup
      @output_format = :console
      @enforcement_mode = false
      @auto_apply_enabled = false # Safety: never auto-apply by default
      @blocking_mode_enabled = false # Safety: non-blocking by default
      @agent_registry = agent_registry || OptimizerRegistry.new

      # LLM Provider configuration
      @llm_provider = :openai
      @openai_config = LLMProviders::OpenAIConfig.new
      @anthropic_config = LLMProviders::AnthropicConfig.new
      @local_llm_config = LLMProviders::LocalLLMConfig.new

      # AI Agent configuration
      @ai_agents_enabled = true # Enable AI agents by default
      @hybrid_mode_enabled = true # Enable hybrid mode (AI + rule-based) by default
      @fallback_to_rule_based = true # Fallback to rule-based agents if AI fails
      @ai_agent_timeout = 30 # Timeout for AI agent requests in seconds

      # File Editing configuration (v2.0)
      @file_editing_enabled = false # Disabled by default for safety
      @backup_directory = nil # Will use default if not set
      @auto_rollback_on_error = true # Rollback changes if errors occur
      @max_changes_per_run = 10 # Limit number of changes per execution
      @require_confirmation = true # Require user confirmation before applying changes
      @dry_run_mode = false # Actually apply changes (not just preview)
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
      unless @agent_registry.optimizer_registered?(agent_sym)
        raise ArgumentError, "Unknown agent: #{agent_name}. Available agents: #{@agent_registry.all_optimizer_types}"
      end

      @enabled_agents << agent_sym unless @enabled_agents.include?(agent_sym)
    end

    def disable_agent(agent_name)
      @enabled_agents.delete(agent_name.to_sym)
    end

    # Alias for enabled_agents= to support optimizer terminology
    def enabled_optimizers=(optimizer_list)
      @enabled_agents = Array(optimizer_list).map(&:to_sym)
    end

    # Alias for enabled_agents to support optimizer terminology
    def enabled_optimizers
      @enabled_agents
    end

    # Register a custom AI agent
    def register_ai_agent(agent_type, agent_class)
      @agent_registry.register_llm_optimizer(agent_type, agent_class)
    end

    # Register a custom rule-based agent
    def register_rule_based_agent(agent_type, agent_class)
      @agent_registry.register_rule_based_optimizer(agent_type, agent_class)
    end

    # Get all available agent types
    def available_agents
      @agent_registry.all_optimizer_types
    end

    # Get enabled agents filtered by registry
    def filtered_enabled_agents
      @agent_registry.enabled_optimizers(@enabled_agents)
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

    # LLM Provider helper methods
    def llm_provider=(provider)
      provider_sym = provider.to_sym
      unless VALID_LLM_PROVIDERS.include?(provider_sym)
        raise ArgumentError, "Invalid LLM provider: #{provider}. Valid providers: #{VALID_LLM_PROVIDERS}"
      end

      @llm_provider = provider_sym
    end

    def current_llm_config
      case @llm_provider
      when :openai
        @openai_config
      when :anthropic
        @anthropic_config
      when :local_llm
        @local_llm_config
      else
        raise ArgumentError, "Unknown LLM provider: #{@llm_provider}"
      end
    end

    def llm_provider_available?
      current_llm_config.complete?
    rescue StandardError
      false
    end

    # AI Agent helper methods
    def ai_agents_enabled?
      @ai_agents_enabled
    end

    def hybrid_mode_enabled?
      @hybrid_mode_enabled
    end

    def fallback_to_rule_based?
      @fallback_to_rule_based
    end

    def ai_agent_timeout_seconds
      @ai_agent_timeout
    end

    # Enable/disable AI agents
    def enable_ai_agents
      @ai_agents_enabled = true
    end

    def disable_ai_agents
      @ai_agents_enabled = false
    end

    # Enable/disable hybrid mode
    def enable_hybrid_mode
      @hybrid_mode_enabled = true
    end

    def disable_hybrid_mode
      @hybrid_mode_enabled = false
    end

    # Set AI agent timeout
    def ai_agent_timeout=(timeout_seconds)
      raise ArgumentError, 'AI agent timeout must be positive' unless timeout_seconds.positive?

      @ai_agent_timeout = timeout_seconds
    end

    # File Editing helper methods (v2.0)
    def file_editing_enabled?
      @file_editing_enabled
    end

    def enable_file_editing
      @file_editing_enabled = true
    end

    def disable_file_editing
      @file_editing_enabled = false
    end

    def backup_directory
      @backup_directory || File.join(Dir.pwd, 'tmp', 'spec_scout_backups')
    end

    def auto_rollback_on_error?
      @auto_rollback_on_error
    end

    def require_confirmation?
      @require_confirmation
    end

    def dry_run_mode?
      @dry_run_mode
    end

    def max_changes_per_run=(max_changes)
      raise ArgumentError, 'Max changes per run must be positive' unless max_changes.positive?

      @max_changes_per_run = max_changes
    end

    # Check if we should use AI agents for a specific agent type
    def use_ai_agent?(agent_type)
      return false unless @ai_agents_enabled
      return false unless llm_provider_available?

      # Check if AI version of the agent is available
      @agent_registry.llm_optimizer_registered?(agent_type)
    end

    # Check if we should use rule-based agents
    def use_rule_based_agents?
      return true unless @ai_agents_enabled
      return true if @hybrid_mode_enabled

      # Use rule-based if AI is not available
      !llm_provider_available?
    end

    # Get execution mode for agents
    def agent_execution_mode
      if @ai_agents_enabled && llm_provider_available?
        if @hybrid_mode_enabled
          :hybrid # Use both AI and rule-based agents
        else
          :ai_only # Use only AI agents
        end
      else
        :rule_based_only # Use only rule-based agents
      end
    end

    def validate!
      # Validate enabled agents against registry
      unregistered_agents = @enabled_agents.reject { |agent| @agent_registry.optimizer_registered?(agent) }
      unless unregistered_agents.empty?
        available_agents = @agent_registry.all_optimizer_types
        raise ArgumentError, "Unregistered agents: #{unregistered_agents}. Available agents: #{available_agents}"
      end

      unless VALID_OUTPUT_FORMATS.include?(@output_format)
        raise ArgumentError, "Invalid output format: #{@output_format}. Valid formats: #{VALID_OUTPUT_FORMATS}"
      end

      unless VALID_LLM_PROVIDERS.include?(@llm_provider)
        raise ArgumentError, "Invalid LLM provider: #{@llm_provider}. Valid providers: #{VALID_LLM_PROVIDERS}"
      end

      # Validate the current LLM provider configuration
      current_llm_config.validate! if llm_provider_available?

      true
    end

    def to_h
      {
        enable: @enable,
        use_test_prof: @use_test_prof,
        fail_on_high_confidence: @fail_on_high_confidence,
        enabled_agents: @enabled_agents,
        available_agents: @agent_registry.all_optimizer_types,
        output_format: @output_format,
        enforcement_mode: @enforcement_mode,
        auto_apply_enabled: @auto_apply_enabled,
        blocking_mode_enabled: @blocking_mode_enabled,
        llm_provider: @llm_provider,
        openai_config: @openai_config.to_h,
        anthropic_config: @anthropic_config.to_h,
        local_llm_config: @local_llm_config.to_h,
        ai_agents_enabled: @ai_agents_enabled,
        hybrid_mode_enabled: @hybrid_mode_enabled,
        fallback_to_rule_based: @fallback_to_rule_based,
        ai_agent_timeout: @ai_agent_timeout,
        agent_execution_mode: agent_execution_mode,
        file_editing_enabled: @file_editing_enabled,
        backup_directory: backup_directory,
        auto_rollback_on_error: @auto_rollback_on_error,
        max_changes_per_run: @max_changes_per_run,
        require_confirmation: @require_confirmation,
        dry_run_mode: @dry_run_mode
      }
    end

    # Create a duplicate configuration for CLI argument parsing
    def dup
      new_config = self.class.new(@agent_registry)
      new_config.enable = @enable
      new_config.use_test_prof = @use_test_prof
      new_config.fail_on_high_confidence = @fail_on_high_confidence
      new_config.enabled_agents = @enabled_agents.dup
      new_config.output_format = @output_format
      new_config.enforcement_mode = @enforcement_mode
      new_config.auto_apply_enabled = @auto_apply_enabled
      new_config.blocking_mode_enabled = @blocking_mode_enabled
      new_config.llm_provider = @llm_provider
      new_config.openai_config = LLMProviders::OpenAIConfig.from_hash(@openai_config.to_h)
      new_config.anthropic_config = LLMProviders::AnthropicConfig.from_hash(@anthropic_config.to_h)
      new_config.local_llm_config = LLMProviders::LocalLLMConfig.from_hash(@local_llm_config.to_h)
      new_config.ai_agents_enabled = @ai_agents_enabled
      new_config.hybrid_mode_enabled = @hybrid_mode_enabled
      new_config.fallback_to_rule_based = @fallback_to_rule_based
      new_config.ai_agent_timeout = @ai_agent_timeout
      new_config.file_editing_enabled = @file_editing_enabled
      new_config.backup_directory = @backup_directory
      new_config.auto_rollback_on_error = @auto_rollback_on_error
      new_config.max_changes_per_run = @max_changes_per_run
      new_config.require_confirmation = @require_confirmation
      new_config.dry_run_mode = @dry_run_mode
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
        when :llm_provider
          self.llm_provider = value
        when :openai_config
          @openai_config = value.is_a?(Hash) ? LLMProviders::OpenAIConfig.from_hash(value) : value
        when :anthropic_config
          @anthropic_config = value.is_a?(Hash) ? LLMProviders::AnthropicConfig.from_hash(value) : value
        when :local_llm_config
          @local_llm_config = value.is_a?(Hash) ? LLMProviders::LocalLLMConfig.from_hash(value) : value
        when :ai_agents_enabled
          @ai_agents_enabled = value
        when :hybrid_mode_enabled
          @hybrid_mode_enabled = value
        when :fallback_to_rule_based
          @fallback_to_rule_based = value
        when :ai_agent_timeout
          self.ai_agent_timeout = value
        when :file_editing_enabled
          @file_editing_enabled = value
        when :backup_directory
          @backup_directory = value
        when :auto_rollback_on_error
          @auto_rollback_on_error = value
        when :max_changes_per_run
          self.max_changes_per_run = value
        when :require_confirmation
          @require_confirmation = value
        when :dry_run_mode
          @dry_run_mode = value
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
