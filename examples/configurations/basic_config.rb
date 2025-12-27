# frozen_string_literal: true

# Basic SpecScout configuration for most Rails applications
# Place this in spec/spec_helper.rb or test/test_helper.rb

require 'spec_scout'

SpecScout.configure do |config|
  # Enable SpecScout analysis
  config.enable = true

  # Use TestProf for profiling data
  config.use_test_prof = true

  # Enable all agents for comprehensive analysis
  config.enabled_agents = %i[database factory intent risk]

  # Console output for development
  config.output_format = :console

  # Safety settings (recommended)
  config.auto_apply_enabled = false
  config.blocking_mode_enabled = false
end
