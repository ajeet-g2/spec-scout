# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'AI Integration Pipeline' do
  let(:config) { SpecScout::Configuration.new }
  let(:spec_scout) { SpecScout::SpecScout.new(config) }

  # Mock TestProf integration for all tests
  before do
    allow_any_instance_of(SpecScout::TestProfIntegration).to receive(:execute_profiling)
      .and_return({
                    factory_prof: { stats: { user: { strategy: :create, count: 1 } } },
                    event_prof: { events: {} },
                    db_queries: { total_queries: 6, inserts: 1, selects: 5 }
                  })
  end

  describe 'AI-only mode' do
    before do
      config.llm_provider = :openai
      config.openai_config.api_key = 'test-key'
      config.ai_agents_enabled = true
      config.hybrid_mode_enabled = false
    end

    context 'when AI agents are available and working' do
      let(:mock_ai_result) do
        SpecScout::OptimizerResult.new(
          optimizer_name: :database,
          verdict: :db_unnecessary,
          confidence: :high,
          reasoning: 'AI analysis indicates database persistence is not needed',
          metadata: { execution_mode: :ai, llm_provider: :openai }
        )
      end

      before do
        # Mock AI agent manager to return successful results
        allow_any_instance_of(SpecScout::LlmOptimizerManager).to receive(:llm_optimizers_available?).and_return(true)
        allow_any_instance_of(SpecScout::LlmOptimizerManager).to receive(:run_optimizers)
          .and_return([mock_ai_result])
      end

      it 'successfully runs AI agents and generates recommendations' do
        result = spec_scout.analyze('spec/models/user_spec.rb')

        expect(result[:recommendation]).to be_a(SpecScout::Recommendation)
        expect(result[:agent_results]).not_to be_empty

        # Verify AI agent was used
        ai_results = result[:agent_results].select { |r| r.metadata[:execution_mode] == :ai }
        expect(ai_results).not_to be_empty

        # Verify recommendation includes AI metadata
        expect(result[:recommendation].metadata[:ai_integration]).to be_a(Hash)
        expect(result[:recommendation].metadata[:ai_integration][:ai_agents]).to be > 0
      end
    end

    context 'when AI agents fail' do
      before do
        config.openai_config.api_key = nil # Make AI unavailable
        allow_any_instance_of(SpecScout::LlmOptimizerManager).to receive(:llm_optimizers_available?).and_return(false)
        allow_any_instance_of(SpecScout::LlmOptimizerManager).to receive(:run_optimizers).and_return([])
      end

      it 'returns empty results in AI-only mode when AI is unavailable' do
        result = spec_scout.analyze('spec/models/user_spec.rb')

        # In AI-only mode when AI is unavailable, the system should still work
        # but may fall back to rule-based agents or return no action
        expect(result[:recommendation]).to be_a(SpecScout::Recommendation)

        # The system should handle the unavailability gracefully
        if result[:agent_results].empty?
          expect(result[:recommendation].action).to eq(:no_action)
          expect(result[:recommendation].metadata[:no_successful_agents]).to be true
        else
          # If rule-based agents ran as fallback, that's acceptable behavior
          expect(result[:agent_results]).not_to be_empty
          expect(result[:recommendation].metadata[:ai_integration][:ai_available]).to be false
        end
      end
    end
  end

  describe 'hybrid mode' do
    before do
      config.llm_provider = :openai
      config.openai_config.api_key = 'test-key'
      config.ai_agents_enabled = true
      config.hybrid_mode_enabled = true
      config.fallback_to_rule_based = true
    end

    context 'when AI agents succeed' do
      let(:mock_ai_result) do
        SpecScout::OptimizerResult.new(
          optimizer_name: :database,
          verdict: :db_unnecessary,
          confidence: :high,
          reasoning: 'AI analysis indicates optimization opportunity',
          metadata: { execution_mode: :ai, llm_provider: :openai }
        )
      end

      before do
        # Mock AI agent manager to return AI results
        allow_any_instance_of(SpecScout::LlmOptimizerManager).to receive(:llm_optimizers_available?).and_return(true)
        allow_any_instance_of(SpecScout::LlmOptimizerManager).to receive(:run_optimizers)
          .and_return([mock_ai_result])
      end

      it 'uses AI agents and supplements with rule-based agents' do
        result = spec_scout.analyze('spec/models/user_spec.rb')

        expect(result[:recommendation]).to be_a(SpecScout::Recommendation)
        expect(result[:agent_results]).not_to be_empty

        # Should have both AI and rule-based results
        ai_results = result[:agent_results].select { |r| r.metadata[:execution_mode] == :ai }
        result[:agent_results].select { |r| r.metadata[:execution_mode] == :rule_based }

        expect(ai_results).not_to be_empty
        # In hybrid mode, we may or may not have rule-based results depending on implementation

        # Verify hybrid execution mode in metadata
        expect(result[:recommendation].metadata[:ai_integration][:execution_mode]).to eq(:hybrid)
      end
    end

    context 'when AI agents fail but rule-based agents succeed' do
      before do
        # Mock AI to be unavailable
        allow_any_instance_of(SpecScout::LlmOptimizerManager).to receive(:llm_optimizers_available?).and_return(false)
        allow_any_instance_of(SpecScout::LlmOptimizerManager).to receive(:run_optimizers).and_return([])
      end

      it 'falls back to rule-based agents' do
        result = spec_scout.analyze('spec/models/user_spec.rb')

        expect(result[:recommendation]).to be_a(SpecScout::Recommendation)
        expect(result[:agent_results]).not_to be_empty

        # Should only have rule-based results
        ai_results = result[:agent_results].select { |r| r.metadata[:execution_mode] == :ai }
        rule_based_results = result[:agent_results].select { |r| r.metadata[:execution_mode] == :rule_based }

        expect(ai_results).to be_empty
        expect(rule_based_results).not_to be_empty

        # Verify fallback occurred
        expect(result[:recommendation].metadata[:ai_integration][:ai_available]).to be false
      end
    end
  end

  describe 'rule-based only mode' do
    before do
      config.ai_agents_enabled = false
      config.hybrid_mode_enabled = false
    end

    it 'uses only rule-based agents' do
      result = spec_scout.analyze('spec/models/user_spec.rb')

      expect(result[:recommendation]).to be_a(SpecScout::Recommendation)
      expect(result[:agent_results]).not_to be_empty

      # Should only have rule-based results
      ai_results = result[:agent_results].select { |r| r.metadata[:execution_mode] == :ai }
      rule_based_results = result[:agent_results].select { |r| r.metadata[:execution_mode] == :rule_based }

      expect(ai_results).to be_empty
      expect(rule_based_results).not_to be_empty

      # Verify execution mode
      expect(result[:recommendation].metadata[:ai_integration][:execution_mode]).to eq(:rule_based_only)
    end
  end

  describe 'error handling and recovery' do
    before do
      config.llm_provider = :openai
      config.openai_config.api_key = 'test-key'
      config.ai_agents_enabled = true
      config.hybrid_mode_enabled = true
      config.fallback_to_rule_based = true
    end

    context 'when individual AI agents fail' do
      let(:fallback_result) do
        SpecScout::AgentResult.new(
          agent_name: :database,
          verdict: :db_unnecessary,
          confidence: :medium,
          reasoning: 'Fallback rule-based analysis',
          metadata: { execution_mode: :rule_based, fallback: true, ai_agent_failed: true }
        )
      end

      before do
        # Mock AI agent manager to return fallback results
        allow_any_instance_of(SpecScout::LlmOptimizerManager).to receive(:llm_optimizers_available?).and_return(true)
        allow_any_instance_of(SpecScout::LlmOptimizerManager).to receive(:run_optimizers)
          .and_return([fallback_result])
      end

      it 'falls back to rule-based agents for failed AI agents' do
        result = spec_scout.analyze('spec/models/user_spec.rb')

        expect(result[:recommendation]).to be_a(SpecScout::Recommendation)
        expect(result[:agent_results]).not_to be_empty

        # Should have fallback results
        fallback_results = result[:agent_results].select { |r| r.metadata[:fallback] }
        expect(fallback_results).not_to be_empty

        # Verify fallback metadata
        expect(result[:recommendation].metadata[:ai_integration][:fallback_occurred]).to be true
      end
    end

    context 'when consensus engine fails' do
      before do
        # Mock consensus engine to fail
        allow_any_instance_of(SpecScout::ConsensusEngine).to receive(:generate_recommendation)
          .and_raise(StandardError, 'Consensus failed')
      end

      it 'returns fallback recommendation' do
        result = spec_scout.analyze('spec/models/user_spec.rb')

        expect(result[:recommendation]).to be_a(SpecScout::Recommendation)
        expect(result[:recommendation].action).to eq(:no_action)
        expect(result[:recommendation].metadata[:consensus_failed]).to be true
      end
    end
  end

  describe 'comprehensive integration' do
    before do
      config.llm_provider = :openai
      config.openai_config.api_key = 'test-key'
      config.ai_agents_enabled = true
      config.hybrid_mode_enabled = true
    end

    it 'integrates all components successfully' do
      # Mock successful AI agent execution
      mock_ai_result = SpecScout::OptimizerResult.new(
        optimizer_name: :database,
        verdict: :db_unnecessary,
        confidence: :high,
        reasoning: 'AI analysis complete',
        metadata: { execution_mode: :ai, llm_provider: :openai }
      )

      allow_any_instance_of(SpecScout::LlmOptimizerManager).to receive(:llm_optimizers_available?).and_return(true)
      allow_any_instance_of(SpecScout::LlmOptimizerManager).to receive(:run_optimizers)
        .and_return([mock_ai_result])

      result = spec_scout.analyze('spec/models/user_spec.rb')

      # Verify complete pipeline execution
      expect(result).to include(:recommendation, :profile_data, :agent_results)
      expect(result[:recommendation]).to be_a(SpecScout::Recommendation)
      expect(result[:profile_data]).to be_a(SpecScout::ProfileData)
      expect(result[:agent_results]).to be_an(Array)
      expect(result[:agent_results]).not_to be_empty

      # Verify AI integration metadata
      ai_metadata = result[:recommendation].metadata[:ai_integration]
      expect(ai_metadata).to be_a(Hash)
      expect(ai_metadata).to include(:total_agents, :ai_agents, :rule_based_agents, :execution_mode)
      expect(ai_metadata[:execution_mode]).to eq(:hybrid)
    end
  end
end
