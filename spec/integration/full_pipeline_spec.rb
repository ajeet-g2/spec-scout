# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Full Pipeline Integration' do
  let(:config) { SpecScout::Configuration.new }
  let(:spec_scout) { SpecScout::SpecScout.new(config) }

  describe 'complete analysis pipeline' do
    it 'successfully processes through all pipeline stages' do
      # Mock TestProf integration to return realistic data
      allow_any_instance_of(SpecScout::TestProfIntegration).to receive(:execute_profiling).and_return({
                                                                                                        factory_prof: {
                                                                                                          stats: {
                                                                                                            user: {
                                                                                                              strategy: :create, count: 3, time: 0.15
                                                                                                            },
                                                                                                            post: {
                                                                                                              strategy: :build, count: 1, time: 0.05
                                                                                                            }
                                                                                                          }
                                                                                                        },
                                                                                                        event_prof: {
                                                                                                          events: {
                                                                                                            'sql.active_record': {
                                                                                                              count: 8, time: 0.25, examples: []
                                                                                                            }
                                                                                                          }
                                                                                                        },
                                                                                                        db_queries: {
                                                                                                          total_queries: 8,
                                                                                                          inserts: 3,
                                                                                                          selects: 5,
                                                                                                          updates: 0,
                                                                                                          deletes: 0
                                                                                                        }
                                                                                                      })

      # Execute the full pipeline
      result = spec_scout.analyze('spec/models/user_spec.rb')

      # Verify pipeline completed successfully
      expect(result).to be_a(Hash)
      expect(result[:recommendation]).to be_a(SpecScout::Recommendation)
      expect(result[:profile_data]).to be_a(SpecScout::ProfileData)
      expect(result[:agent_results]).to be_an(Array)
      expect(result[:agent_results]).not_to be_empty

      # Verify profile data was normalized correctly
      profile_data = result[:profile_data]
      expect(profile_data.example_location).to eq('spec/models/user_spec.rb')
      expect(profile_data.spec_type).to eq(:model)
      expect(profile_data.factories).to be_a(Hash)
      expect(profile_data.db).to be_a(Hash)

      # Verify agents ran and produced results
      agent_results = result[:agent_results]
      agent_names = agent_results.map(&:agent_name)
      expect(agent_names).to include(:database, :factory, :intent, :risk)

      # Verify each agent result has required fields
      agent_results.each do |agent_result|
        expect(agent_result.verdict).not_to be_nil
        expect(%i[high medium low none]).to include(agent_result.confidence)
        expect(agent_result.reasoning).to be_a(String)
        expect(agent_result.metadata).to be_a(Hash)
      end

      # Verify recommendation was generated
      recommendation = result[:recommendation]
      expect(recommendation.spec_location).to be_a(String)
      expect(recommendation.action).not_to be_nil
      expect(%i[high medium low none]).to include(recommendation.confidence)
      expect(recommendation.explanation).to be_an(Array)
    end

    it 'handles pipeline errors gracefully' do
      # Mock TestProf to fail
      allow_any_instance_of(SpecScout::TestProfIntegration).to receive(:execute_profiling)
        .and_raise(SpecScout::TestProfIntegration::TestProfError, 'TestProf failed')

      result = spec_scout.analyze('spec/models/user_spec.rb')

      # Should return no_profile_data result instead of crashing
      expect(result[:no_profile_data]).to be true
      expect(result[:should_fail]).to be false
      expect(result[:recommendation]).to be_nil
    end

    it 'processes enforcement mode correctly' do
      config.enforcement_mode = true
      config.fail_on_high_confidence = true

      # Mock pipeline to return high confidence recommendation
      allow_any_instance_of(SpecScout::TestProfIntegration).to receive(:execute_profiling).and_return({
                                                                                                        factory_prof: { stats: {} },
                                                                                                        event_prof: { events: {} },
                                                                                                        db_queries: {
                                                                                                          total_queries: 0, inserts: 0, selects: 0
                                                                                                        }
                                                                                                      })

      # Mock consensus to return high confidence recommendation
      mock_recommendation = SpecScout::Recommendation.new(
        spec_location: 'spec/models/user_spec.rb',
        action: :replace_factory_strategy,
        from_value: 'create(:user)',
        to_value: 'build_stubbed(:user)',
        confidence: :high,
        explanation: ['High confidence optimization'],
        agent_results: []
      )

      allow_any_instance_of(SpecScout::ConsensusEngine).to receive(:generate_recommendation)
        .and_return(mock_recommendation)

      result = spec_scout.analyze('spec/models/user_spec.rb')

      # Should set should_fail for high confidence in enforcement mode
      expect(result[:should_fail]).to be true
      expect(result[:exit_code]).to eq(1)
      expect(result[:enforcement_message]).to include('High confidence recommendation')
    end
  end

  describe 'error recovery and logging' do
    it 'continues processing when individual agents fail' do
      # Mock TestProf to return data
      allow_any_instance_of(SpecScout::TestProfIntegration).to receive(:execute_profiling).and_return({
                                                                                                        factory_prof: { stats: {} },
                                                                                                        event_prof: { events: {} },
                                                                                                        db_queries: {
                                                                                                          total_queries: 0, inserts: 0, selects: 0
                                                                                                        }
                                                                                                      })

      # Mock one agent to fail
      allow_any_instance_of(SpecScout::Agents::DatabaseAgent).to receive(:evaluate)
        .and_raise(StandardError, 'Database agent failed')

      # Other agents should still work
      allow_any_instance_of(SpecScout::Agents::FactoryAgent).to receive(:evaluate).and_return(
        { verdict: :strategy_optimal, confidence: :medium, reasoning: 'Factory strategy is good' }
      )

      result = spec_scout.analyze('spec/models/user_spec.rb')

      # Should continue with successful agents
      expect(result[:recommendation]).not_to be_nil
      expect(result[:agent_results]).not_to be_empty

      # Should have results from successful agents only
      successful_agents = result[:agent_results].reject { |r| r.verdict == :agent_failed }
      expect(successful_agents).not_to be_empty
    end

    it 'provides debug logging when enabled' do
      ENV['SPEC_SCOUT_DEBUG'] = 'true'

      # Capture output
      output = StringIO.new
      allow($stdout).to receive(:puts) { |msg| output.puts(msg) }

      # Mock TestProf to return data
      allow_any_instance_of(SpecScout::TestProfIntegration).to receive(:execute_profiling).and_return({
                                                                                                        factory_prof: { stats: {} },
                                                                                                        event_prof: { events: {} },
                                                                                                        db_queries: {
                                                                                                          total_queries: 0, inserts: 0, selects: 0
                                                                                                        }
                                                                                                      })

      spec_scout.analyze('spec/models/user_spec.rb')

      # Should include debug messages
      output_string = output.string
      expect(output_string).to include('[DEBUG] SpecScout:')
      expect(output_string).to include('Starting SpecScout analysis')

      ENV.delete('SPEC_SCOUT_DEBUG')
    end
  end
end
