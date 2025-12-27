# frozen_string_literal: true

# Development-focused SpecScout configuration
# Optimized for local development and debugging

require 'spec_scout'

SpecScout.configure do |config|
  # Enable SpecScout for development
  config.enable = true

  # Use TestProf integration
  config.use_test_prof = true

  # Enable all agents for comprehensive feedback
  config.enabled_agents = %i[database factory intent risk]

  # Console output for immediate feedback
  config.output_format = :console

  # Non-enforcement mode for development
  config.enforcement_mode = false
  config.fail_on_high_confidence = false

  # Safety settings
  config.auto_apply_enabled = false
  config.blocking_mode_enabled = false
end

# Enable debug mode for development
ENV['SPEC_SCOUT_DEBUG'] = '1' if Rails.env.development?

# Example development workflow:
# 1. Run specs: bundle exec rspec spec/models/user_spec.rb
# 2. Review SpecScout recommendations
# 3. Apply optimizations manually
# 4. Re-run specs to verify improvements
