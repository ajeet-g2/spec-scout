# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SpecScout::SpecScout do
  let(:config) { SpecScout::Configuration.new }
  let(:spec_scout) { described_class.new(config) }

  describe '#initialize' do
    it 'uses provided configuration' do
      expect(spec_scout.config).to eq(config)
    end

    it 'uses default configuration when none provided' do
      scout = described_class.new
      expect(scout.config).to be_a(SpecScout::Configuration)
    end

    it 'validates configuration on initialization' do
      invalid_config = SpecScout::Configuration.new

      expect { invalid_config.output_format = :invalid }.to raise_error(ArgumentError)
    end
  end

  describe '#analyze' do
    context 'when disabled' do
      before { config.enable = false }

      it 'returns disabled result' do
        result = spec_scout.analyze

        expect(result[:disabled]).to be true
        expect(result[:recommendation]).to be_nil
        expect(result[:should_fail]).to be false
      end
    end

    context 'when TestProf is disabled' do
      before { config.use_test_prof = false }

      it 'returns no profile data result' do
        result = spec_scout.analyze

        expect(result[:no_profile_data]).to be true
        expect(result[:recommendation]).to be_nil
        expect(result[:should_fail]).to be false
      end
    end

    context 'when no agents are enabled' do
      before { config.enabled_agents = [] }

      it 'returns no agents result' do
        # Mock TestProf integration to return some data
        allow_any_instance_of(SpecScout::TestProfIntegration).to receive(:execute_profiling).and_return({
                                                                                                          factory_prof: { stats: {} },
                                                                                                          event_prof: { events: {} },
                                                                                                          db_queries: {
                                                                                                            total_queries: 0, inserts: 0, selects: 0
                                                                                                          }
                                                                                                        })

        allow_any_instance_of(SpecScout::ProfileNormalizer).to receive(:normalize).and_return(
          SpecScout::ProfileData.new(
            example_location: 'spec/test_spec.rb:10',
            spec_type: :model,
            runtime_ms: 100,
            factories: {},
            db: {},
            events: {},
            metadata: {}
          )
        )

        result = spec_scout.analyze

        expect(result[:no_agents]).to be true
        expect(result[:recommendation]).to be_nil
        expect(result[:should_fail]).to be false
      end
    end
  end

  describe '.analyze_spec' do
    it 'creates a new instance and analyzes' do
      expect(described_class).to receive(:new).with(config).and_call_original
      expect_any_instance_of(described_class).to receive(:analyze).with('spec/test_spec.rb')

      described_class.analyze_spec('spec/test_spec.rb', config)
    end

    it 'uses default config when none provided' do
      expect(described_class).to receive(:new).with(nil).and_call_original
      expect_any_instance_of(described_class).to receive(:analyze).with(nil)

      described_class.analyze_spec
    end
  end

  describe 'error handling' do
    it 'handles TestProf integration errors gracefully' do
      allow_any_instance_of(SpecScout::TestProfIntegration).to receive(:execute_profiling).and_raise(StandardError,
                                                                                                     'TestProf failed')

      result = spec_scout.analyze

      expect(result[:no_profile_data]).to be true
      expect(result[:should_fail]).to be false
    end

    it 'handles agent execution errors gracefully' do
      # Mock TestProf to return data
      allow_any_instance_of(SpecScout::TestProfIntegration).to receive(:execute_profiling).and_return({})
      allow_any_instance_of(SpecScout::ProfileNormalizer).to receive(:normalize).and_return(
        SpecScout::ProfileData.new(
          example_location: 'spec/test_spec.rb:10',
          spec_type: :model,
          runtime_ms: 100,
          factories: {},
          db: {},
          events: {},
          metadata: {}
        )
      )

      # Mock agent to fail
      allow_any_instance_of(SpecScout::Agents::DatabaseAgent).to receive(:evaluate).and_raise(StandardError,
                                                                                              'Agent failed')

      result = spec_scout.analyze

      # Should continue with other agents and not fail completely
      expect(result[:error]).to be_nil
      expect(result[:agent_results]).to be_an(Array)
    end
  end

  describe 'enforcement mode' do
    before do
      config.enforcement_mode = true
      config.fail_on_high_confidence = true
    end

    it 'sets should_fail for high confidence recommendations' do
      # Mock the full pipeline to return a high confidence recommendation
      allow_any_instance_of(SpecScout::TestProfIntegration).to receive(:execute_profiling).and_return({
                                                                                                        factory_prof: { stats: {} },
                                                                                                        event_prof: { events: {} },
                                                                                                        db_queries: {
                                                                                                          total_queries: 0, inserts: 0, selects: 0
                                                                                                        }
                                                                                                      })

      allow_any_instance_of(SpecScout::ProfileNormalizer).to receive(:normalize).and_return(
        SpecScout::ProfileData.new(
          example_location: 'spec/test_spec.rb:10',
          spec_type: :model,
          runtime_ms: 100,
          factories: {},
          db: {},
          events: {},
          metadata: {}
        )
      )

      # Mock agents to return results
      allow_any_instance_of(SpecScout::Agents::DatabaseAgent).to receive(:evaluate).and_return(
        { verdict: :db_unnecessary, confidence: :high, reasoning: 'Test reasoning' }
      )

      # Mock consensus engine to return high confidence recommendation
      mock_recommendation = SpecScout::Recommendation.new(
        spec_location: 'spec/test_spec.rb:10',
        action: :replace_factory_strategy,
        from_value: 'create(:user)',
        to_value: 'build_stubbed(:user)',
        confidence: :high,
        explanation: ['High confidence optimization'],
        agent_results: []
      )

      allow_any_instance_of(SpecScout::ConsensusEngine).to receive(:generate_recommendation).and_return(mock_recommendation)

      result = spec_scout.analyze

      expect(result[:should_fail]).to be true
    end
  end
end
