#!/usr/bin/env ruby
# frozen_string_literal: true

# Demo script showing OutputFormatter in action
require_relative '../lib/spec_scout'

# Create sample profile data
profile_data = SpecScout::ProfileData.new(
  example_location: 'spec/models/user_spec.rb:42',
  spec_type: :model,
  runtime_ms: 38,
  factories: { user: { strategy: :create, count: 1 } },
  db: { total_queries: 6, inserts: 1, selects: 5 },
  events: {},
  metadata: {}
)

# Create sample agent results
agent_results = [
  SpecScout::AgentResult.new(
    agent_name: :database,
    verdict: :db_unnecessary,
    confidence: :high,
    reasoning: 'No database writes detected',
    metadata: {}
  ),
  SpecScout::AgentResult.new(
    agent_name: :factory,
    verdict: :prefer_build_stubbed,
    confidence: :medium,
    reasoning: 'Factory can use build_stubbed',
    metadata: {}
  ),
  SpecScout::AgentResult.new(
    agent_name: :intent,
    verdict: :unit_test_behavior,
    confidence: :high,
    reasoning: 'Test behaves like unit test',
    metadata: {}
  ),
  SpecScout::AgentResult.new(
    agent_name: :risk,
    verdict: :safe_to_optimize,
    confidence: :high,
    reasoning: 'No side effects detected',
    metadata: {}
  )
]

# Create sample recommendation
recommendation = SpecScout::Recommendation.new(
  spec_location: 'spec/models/user_spec.rb:42',
  action: :replace_factory_strategy,
  from_value: 'create(:user)',
  to_value: 'build_stubbed(:user)',
  confidence: :high,
  explanation: [
    'Strong agreement supports optimization recommendation',
    '4 agent(s) agree on optimize_persistence approach',
    'No risk factors detected'
  ],
  agent_results: agent_results
)

# Format and display the recommendation
formatter = SpecScout::OutputFormatter.new(recommendation, profile_data)
puts formatter.format_recommendation
