# frozen_string_literal: true

# Conservative SpecScout configuration
# Focuses on safe optimizations and avoids risky changes

require 'spec_scout'

SpecScout.configure do |config|
  # Enable SpecScout
  config.enable = true

  # Use TestProf integration
  config.use_test_prof = true

  # Enable risk agent to identify unsafe optimizations
  # Disable intent agent to avoid boundary-related recommendations
  config.enabled_agents = %i[database factory risk]

  # Console output for manual review
  config.output_format = :console

  # Non-enforcement mode for safety
  config.enforcement_mode = false
  config.fail_on_high_confidence = false

  # Safety settings (always recommended)
  config.auto_apply_enabled = false
  config.blocking_mode_enabled = false
end

# This configuration prioritizes safety over optimization speed
# Recommendations will be conservative and well-validated
