# frozen_string_literal: true

require 'timeout'
require_relative 'llm_providers'
require_relative 'context_builder'
require_relative 'response_parser'
require_relative 'optimizer_registry'

module SpecScout
  # LLM Optimizer Manager orchestrates LLM-powered optimizers and manages fallback to rule-based optimizers
  class LlmOptimizerManager
    # Custom error class for LLM optimizer failures
    class LlmOptimizerError < StandardError; end

    attr_reader :config, :llm_provider, :optimizer_registry, :context_builder, :response_parser

    def initialize(config)
      @config = config
      @llm_provider = create_llm_provider
      @optimizer_registry = OptimizerRegistry.new
      @context_builder = ContextBuilder.new
      @response_parser = ResponseParser.new
    end

    # Run LLM optimizers and return aggregated results
    # Falls back to rule-based optimizers if LLM optimizers fail
    def run_optimizers(profile_data, spec_content = nil)
      log_debug("Starting LLM optimizer execution with #{enabled_llm_optimizers.size} enabled LLM optimizers")

      # Validate inputs
      unless profile_data.is_a?(ProfileData) && profile_data.valid?
        log_error('Invalid profile data provided to LLM optimizer manager')
        return []
      end

      llm_results = []
      fallback_results = []

      enabled_llm_optimizers.each do |optimizer_type|
        log_debug("Running LLM optimizer: #{optimizer_type}")

        begin
          result = run_single_llm_optimizer(optimizer_type, profile_data, spec_content)

          if result && result.verdict != :optimizer_failed
            llm_results << result
            log_debug("LLM optimizer #{optimizer_type} succeeded: #{result.verdict} (#{result.confidence})")
          else
            log_debug("LLM optimizer #{optimizer_type} failed, attempting fallback")
            fallback_result = run_fallback_optimizer(optimizer_type, profile_data)
            fallback_results << fallback_result if fallback_result
          end
        rescue StandardError => e
          log_error("LLM optimizer #{optimizer_type} failed with error: #{e.message}")
          log_debug("LLM optimizer #{optimizer_type} backtrace: #{e.backtrace.join("\n")}") if debug_enabled?

          # Attempt fallback to rule-based optimizer
          fallback_result = run_fallback_optimizer(optimizer_type, profile_data)
          fallback_results << fallback_result if fallback_result
        end
      end

      all_results = llm_results + fallback_results
      log_debug("LLM optimizer execution completed: #{llm_results.size} LLM results, #{fallback_results.size} fallback results")

      # Validate all results before returning
      validate_llm_optimizer_results(all_results)
    rescue StandardError => e
      log_error("LLM optimizer manager execution failed: #{e.message}")
      log_debug("LLM optimizer manager backtrace: #{e.backtrace.join("\n")}") if debug_enabled?

      # Return empty results on complete failure
      []
    end

    # Validate LLM optimizer results
    def validate_llm_optimizer_results(results)
      return [] if results.empty?

      validated_results = []

      results.each do |result|
        if result.is_a?(OptimizerResult) && result.valid?
          validated_results << result
        else
          log_error("Invalid LLM optimizer result: #{result.inspect}")
        end
      end

      log_debug("LLM optimizer validation: #{validated_results.size}/#{results.size} results valid")
      validated_results
    end

    # Check if LLM optimizers are available and configured
    def llm_optimizers_available?
      return false unless @config.llm_provider_available?
      return false unless @llm_provider

      enabled_llm_optimizers.any?
    end

    # Get list of enabled LLM optimizer types
    def enabled_llm_optimizers
      @config.enabled_agents.select { |optimizer| llm_optimizer_supported?(optimizer) }
    end

    # Check if an optimizer type is supported as an LLM optimizer
    def llm_optimizer_supported?(optimizer_type)
      @optimizer_registry.llm_optimizer_registered?(optimizer_type)
    end

    # Register a custom LLM optimizer
    def register_llm_optimizer(optimizer_type, optimizer_class)
      @optimizer_registry.register_llm_optimizer(optimizer_type, optimizer_class)
    end

    private

    def create_llm_provider
      return nil unless @config.llm_provider_available?

      begin
        LLMProviders.create_provider(@config.llm_provider, @config.current_llm_config)
      rescue StandardError => e
        log_error("Failed to create LLM provider: #{e.message}")
        nil
      end
    end

    def run_single_llm_optimizer(optimizer_type, profile_data, spec_content)
      return nil unless @llm_provider

      begin
        # Build context for the LLM optimizer with timeout
        @context_builder.build_context(profile_data, spec_content, optimizer_type)

        # Get the LLM optimizer class from registry
        optimizer_class = @optimizer_registry.get_llm_optimizer(optimizer_type)
        return nil unless optimizer_class

        # Create and run the LLM optimizer with timeout
        optimizer = optimizer_class.new(
          optimizer_type: optimizer_type,
          llm_provider: @llm_provider,
          context_builder: @context_builder,
          response_parser: @response_parser
        )

        # Execute the LLM optimizer with timeout
        result = execute_with_timeout(optimizer, profile_data, spec_content)

        # Validate and enhance the result
        if result.is_a?(OptimizerResult)
          result.metadata[:execution_mode] = :llm
          result.metadata[:llm_provider] = @config.llm_provider
          result.metadata[:timestamp] = Time.now
          result
        else
          log_error("LLM optimizer #{optimizer_type} returned invalid result type: #{result.class}")
          create_failed_result(optimizer_type, "Invalid result type: #{result.class}")
        end
      rescue StandardError => e
        log_error("LLM optimizer #{optimizer_type} execution failed: #{e.message}")
        log_debug("LLM optimizer #{optimizer_type} backtrace: #{e.backtrace.join("\n")}") if debug_enabled?
        create_failed_result(optimizer_type, e.message)
      end
    end

    # Execute LLM optimizer with timeout
    def execute_with_timeout(optimizer, profile_data, spec_content)
      timeout_seconds = @config.ai_agent_timeout_seconds

      if timeout_seconds.positive?
        begin
          Timeout.timeout(timeout_seconds) do
            optimizer.analyze(profile_data, spec_content)
          end
        rescue Timeout::Error
          log_error("LLM optimizer execution timed out after #{timeout_seconds} seconds")
          raise StandardError, "LLM optimizer execution timed out after #{timeout_seconds} seconds"
        end
      else
        optimizer.analyze(profile_data, spec_content)
      end
    end

    def run_fallback_optimizer(optimizer_type, profile_data)
      log_debug("Running fallback rule-based optimizer for: #{optimizer_type}")

      begin
        optimizer = create_rule_based_optimizer(optimizer_type, profile_data)
        return nil unless optimizer

        result = optimizer.evaluate

        # Convert to OptimizerResult if needed and mark as fallback
        optimizer_result = ensure_optimizer_result(result, optimizer_type)
        optimizer_result.metadata[:fallback] = true
        optimizer_result.metadata[:llm_optimizer_failed] = true
        optimizer_result.metadata[:execution_mode] = :rule_based
        optimizer_result.metadata[:timestamp] = Time.now

        log_debug("Fallback optimizer #{optimizer_type} completed: #{optimizer_result.verdict} (#{optimizer_result.confidence})")
        optimizer_result
      rescue StandardError => e
        log_error("Fallback optimizer #{optimizer_type} also failed: #{e.message}")
        log_debug("Fallback optimizer #{optimizer_type} backtrace: #{e.backtrace.join("\n")}") if debug_enabled?
        create_failed_result(optimizer_type, "Both LLM and fallback optimizers failed: #{e.message}")
      end
    end

    # Ensure result is an OptimizerResult object
    def ensure_optimizer_result(result, optimizer_name)
      if result.is_a?(OptimizerResult)
        result
      elsif result.is_a?(Hash)
        # Convert Hash to OptimizerResult for consistency
        OptimizerResult.new(
          optimizer_name: optimizer_name,
          verdict: result[:verdict],
          confidence: result[:confidence],
          reasoning: result[:reasoning],
          metadata: result[:metadata] || {}
        )
      else
        # Create a failed result for unexpected types
        create_failed_result(optimizer_name, "Unexpected result type: #{result.class}")
      end
    end

    def create_rule_based_optimizer(optimizer_type, profile_data)
      optimizer_class = @optimizer_registry.get_rule_based_optimizer(optimizer_type)

      if optimizer_class
        optimizer_class.new(profile_data)
      else
        log_error("No rule-based optimizer registered for type: #{optimizer_type}")
        nil
      end
    end

    def create_failed_result(optimizer_type, error_message)
      OptimizerResult.new(
        optimizer_name: optimizer_type,
        verdict: :optimizer_failed,
        confidence: :none,
        reasoning: error_message,
        metadata: {
          error: true,
          timestamp: Time.now,
          llm_optimizer_failed: true
        }
      )
    end

    # Logging helpers
    def log_debug(message)
      return unless debug_enabled?
      return unless @config.console_output?

      puts "[DEBUG] LlmOptimizerManager: #{message}"
    end

    def log_error(message)
      return unless @config.console_output?

      warn "[ERROR] LlmOptimizerManager: #{message}"
    end

    def debug_enabled?
      ENV['SPEC_SCOUT_DEBUG'] == 'true' || @config.debug_mode?
    end
  end
end
