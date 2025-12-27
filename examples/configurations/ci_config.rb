# frozen_string_literal: true

# CI-friendly SpecScout configuration
# Optimized for continuous integration environments

require 'spec_scout'

SpecScout.configure do |config|
  # Enable SpecScout in CI
  config.enable = true

  # Use TestProf integration
  config.use_test_prof = true

  # Enable enforcement mode for CI
  config.enforcement_mode = true
  config.fail_on_high_confidence = true

  # Focus on performance-critical agents
  config.enabled_agents = %i[database factory]

  # JSON output for CI processing
  config.output_format = :json

  # Safety settings
  config.auto_apply_enabled = false
  config.blocking_mode_enabled = false
end

# Example CI usage:
# bundle exec spec_scout --enforce --output json > spec_scout_results.json
#
# Exit codes:
# 0 - No high confidence recommendations
# 1 - High confidence recommendations found (CI should fail)
