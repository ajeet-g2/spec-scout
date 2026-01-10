# frozen_string_literal: true

require_relative 'spec_scout/version'
require_relative 'spec_scout/profile_data'
require_relative 'spec_scout/agent_result'
require_relative 'spec_scout/optimizer_result'
require_relative 'spec_scout/recommendation'
require_relative 'spec_scout/code_change'
require_relative 'spec_scout/code_change_collection'
require_relative 'spec_scout/file_editor'
require_relative 'spec_scout/base_optimizer'
require_relative 'spec_scout/base_llm_optimizer'
require_relative 'spec_scout/configuration'
require_relative 'spec_scout/safety_validator'
require_relative 'spec_scout/enforcement_handler'
require_relative 'spec_scout/testprof_integration'
require_relative 'spec_scout/profile_normalizer'
require_relative 'spec_scout/consensus_engine'
require_relative 'spec_scout/output_formatter'

# LLM Providers
require_relative 'spec_scout/llm_providers'
require_relative 'spec_scout/context_builder'
require_relative 'spec_scout/response_parser'
require_relative 'spec_scout/optimizer_registry'
require_relative 'spec_scout/llm_optimizer_manager'

# Rule-Based Optimizers
require_relative 'spec_scout/optimizers/rule_based/database_optimiser'
require_relative 'spec_scout/optimizers/rule_based/factory_optimiser'
require_relative 'spec_scout/optimizers/rule_based/intent_optimiser'
require_relative 'spec_scout/optimizers/rule_based/risk_optimiser'

# LLM-Based Optimizers
require_relative 'spec_scout/optimizers/llm_based/database_optimiser'
require_relative 'spec_scout/optimizers/llm_based/factory_optimiser'
require_relative 'spec_scout/optimizers/llm_based/intent_optimiser'
require_relative 'spec_scout/optimizers/llm_based/risk_optimiser'

# Main orchestration class
require_relative 'spec_scout/spec_scout'
require_relative 'spec_scout/cli'

# Main module for Spec Scout, a tool for analyzing and optimizing test suite database and factory usage.
module SpecScout
  class Error < StandardError; end

  # Main entry point for Spec Scout functionality
  def self.configure
    yield(configuration) if block_given?
    configuration
  end

  def self.configuration
    @configuration ||= Configuration.new
  end

  def self.reset_configuration!
    @configuration = nil
  end
end
