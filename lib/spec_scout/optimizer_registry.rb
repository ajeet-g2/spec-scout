# frozen_string_literal: true

require_relative 'optimizers/rule_based/database_optimiser'
require_relative 'optimizers/rule_based/factory_optimiser'
require_relative 'optimizers/rule_based/intent_optimiser'
require_relative 'optimizers/rule_based/risk_optimiser'
require_relative 'optimizers/llm_based/database_optimiser'
require_relative 'optimizers/llm_based/factory_optimiser'
require_relative 'optimizers/llm_based/intent_optimiser'
require_relative 'optimizers/llm_based/risk_optimiser'

module SpecScout
  # Registry for managing optimizers and their configurations
  class OptimizerRegistry
    def initialize
      @llm_optimizers = {}
      @rule_based_optimizers = {}
      register_default_optimizers
    end

    # Register an LLM optimizer class
    def register_llm_optimizer(optimizer_type, optimizer_class)
      validate_optimizer_type!(optimizer_type)
      validate_llm_optimizer_class!(optimizer_class)

      @llm_optimizers[optimizer_type.to_sym] = optimizer_class
    end

    # Register a rule-based optimizer class
    def register_rule_based_optimizer(optimizer_type, optimizer_class)
      validate_optimizer_type!(optimizer_type)
      validate_rule_based_optimizer_class!(optimizer_class)

      @rule_based_optimizers[optimizer_type.to_sym] = optimizer_class
    end

    # Get LLM optimizer class for a given type
    def get_llm_optimizer(optimizer_type)
      @llm_optimizers[optimizer_type.to_sym]
    end

    # Get rule-based optimizer class for a given type
    def get_rule_based_optimizer(optimizer_type)
      @rule_based_optimizers[optimizer_type.to_sym]
    end

    # Check if an LLM optimizer is registered for the given type
    def llm_optimizer_registered?(optimizer_type)
      @llm_optimizers.key?(optimizer_type.to_sym)
    end

    # Check if a rule-based optimizer is registered for the given type
    def rule_based_optimizer_registered?(optimizer_type)
      @rule_based_optimizers.key?(optimizer_type.to_sym)
    end

    # Get all registered LLM optimizer types
    def llm_optimizer_types
      @llm_optimizers.keys
    end

    # Get all registered rule-based optimizer types
    def rule_based_optimizer_types
      @rule_based_optimizers.keys
    end

    # Get all registered optimizer types (both LLM and rule-based)
    def all_optimizer_types
      (@llm_optimizers.keys + @rule_based_optimizers.keys).uniq
    end

    # Check if any optimizer (LLM or rule-based) is registered for the given type
    def optimizer_registered?(optimizer_type)
      llm_optimizer_registered?(optimizer_type) || rule_based_optimizer_registered?(optimizer_type)
    end

    # Get enabled optimizers from configuration
    def enabled_optimizers(enabled_optimizer_list)
      enabled_optimizer_list.select { |optimizer_type| optimizer_registered?(optimizer_type) }
    end

    # Clear all registered optimizers (useful for testing)
    def clear_all_optimizers
      @llm_optimizers.clear
      @rule_based_optimizers.clear
    end

    # Reset to default optimizers
    def reset_to_defaults
      clear_all_optimizers
      register_default_optimizers
    end

    private

    def register_default_optimizers
      # Register default rule-based optimizers
      @rule_based_optimizers[:database] = Optimizers::RuleBased::DatabaseOptimiser
      @rule_based_optimizers[:factory] = Optimizers::RuleBased::FactoryOptimiser
      @rule_based_optimizers[:intent] = Optimizers::RuleBased::IntentOptimiser
      @rule_based_optimizers[:risk] = Optimizers::RuleBased::RiskOptimiser

      # Register LLM optimizers
      @llm_optimizers[:database] = Optimizers::LlmBased::DatabaseOptimiser
      @llm_optimizers[:factory] = Optimizers::LlmBased::FactoryOptimiser
      @llm_optimizers[:intent] = Optimizers::LlmBased::IntentOptimiser
      @llm_optimizers[:risk] = Optimizers::LlmBased::RiskOptimiser
    end

    def validate_optimizer_type!(optimizer_type)
      return if optimizer_type.is_a?(Symbol) || optimizer_type.is_a?(String)

      raise ArgumentError, "Optimizer type must be a Symbol or String, got #{optimizer_type.class}"

      # Allow any optimizer type for extensibility
      # The core types are: database, factory, intent, risk
      # But custom optimizers should be allowed
    end

    def validate_llm_optimizer_class!(optimizer_class)
      return if optimizer_class.is_a?(Class)

      raise ArgumentError, "LLM optimizer must be a Class, got #{optimizer_class.class}"

      # LLM optimizers should respond to :new and have an :analyze method
      # We'll validate the interface when LLM optimizers are implemented
    end

    def validate_rule_based_optimizer_class!(optimizer_class)
      unless optimizer_class.is_a?(Class)
        raise ArgumentError,
              "Rule-based optimizer must be a Class, got #{optimizer_class.class}"
      end

      # Rule-based optimizers should inherit from BaseOptimizer
      return if optimizer_class.ancestors.include?(BaseOptimizer)

      raise ArgumentError, 'Rule-based optimizer must inherit from BaseOptimizer'
    end
  end
end
