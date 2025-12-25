# frozen_string_literal: true

require_relative 'spec_scout/version'
require_relative 'spec_scout/profile_data'
require_relative 'spec_scout/agent_result'
require_relative 'spec_scout/recommendation'
require_relative 'spec_scout/base_agent'
require_relative 'spec_scout/configuration'
require_relative 'spec_scout/testprof_integration'
require_relative 'spec_scout/profile_normalizer'

# Agents
require_relative 'spec_scout/agents/database_agent'
require_relative 'spec_scout/agents/factory_agent'
require_relative 'spec_scout/agents/intent_agent'
require_relative 'spec_scout/agents/risk_agent'

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
