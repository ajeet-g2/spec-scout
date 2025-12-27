# frozen_string_literal: true

# Performance-focused SpecScout configuration
# Optimized for maximum test suite speed improvements

require 'spec_scout'

SpecScout.configure do |config|
  # Enable SpecScout
  config.enable = true

  # Use TestProf integration
  config.use_test_prof = true

  # Focus on performance-critical agents
  # Skip risk agent for more aggressive optimizations
  config.enabled_agents = %i[database factory intent]

  # JSON output for automated processing
  config.output_format = :json

  # Enable enforcement for performance gains
  config.enforcement_mode = true
  config.fail_on_high_confidence = true

  # Safety settings (still recommended)
  config.auto_apply_enabled = false
  config.blocking_mode_enabled = false
end

# This configuration prioritizes performance improvements
# Use with caution - test thoroughly after applying recommendations
#
# Recommended workflow:
# 1. Run with enforcement to identify high-impact optimizations
# 2. Apply recommendations in small batches
# 3. Run full test suite after each batch
# 4. Monitor for any behavioral changes
