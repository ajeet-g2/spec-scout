# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SpecScout::ConsensusEngine do
  let(:profile_data) do
    SpecScout::ProfileData.new(
      example_location: 'spec/models/user_spec.rb:42',
      spec_type: :model,
      runtime_ms: 38,
      factories: { user: { strategy: :create, count: 1 } },
      db: { total_queries: 6, inserts: 1, selects: 5 },
      events: {},
      metadata: {}
    )
  end

  let(:db_agent_result) do
    SpecScout::AgentResult.new(
      agent_name: :database,
      verdict: :db_unnecessary,
      confidence: :high,
      reasoning: 'No database writes detected',
      metadata: { insert_count: 0, select_count: 3 }
    )
  end

  let(:factory_agent_result) do
    SpecScout::AgentResult.new(
      agent_name: :factory,
      verdict: :prefer_build_stubbed,
      confidence: :medium,
      reasoning: 'Factory can use build_stubbed',
      metadata: {}
    )
  end

  let(:risk_agent_result) do
    SpecScout::AgentResult.new(
      agent_name: :risk,
      verdict: :safe_to_optimize,
      confidence: :high,
      reasoning: 'No risk factors detected',
      metadata: { risk_score: 0 }
    )
  end

  describe '#initialize' do
    it 'accepts valid agent results and profile data' do
      engine = described_class.new([db_agent_result], profile_data)
      expect(engine.agent_results).to eq([db_agent_result])
      expect(engine.profile_data).to eq(profile_data)
    end

    it 'filters out invalid agent results' do
      invalid_result = SpecScout::AgentResult.new(confidence: :invalid)
      engine = described_class.new([db_agent_result, invalid_result], profile_data)
      expect(engine.agent_results).to eq([db_agent_result])
    end

    it 'raises error for invalid profile data' do
      expect do
        described_class.new([db_agent_result], 'invalid')
      end.to raise_error(ArgumentError, 'Profile data must be a ProfileData instance')
    end
  end

  describe '#generate_recommendation' do
    context 'with no agent results' do
      it 'returns no action recommendation' do
        engine = described_class.new([], profile_data)
        recommendation = engine.generate_recommendation

        expect(recommendation.action).to eq(:no_action)
        expect(recommendation.confidence).to eq(:low)
        expect(recommendation.explanation).to include('No valid agent results available for analysis')
      end
    end

    context 'with strong agreement for optimization' do
      it 'generates strong optimization recommendation' do
        agent_results = [db_agent_result, factory_agent_result, risk_agent_result]
        engine = described_class.new(agent_results, profile_data)
        recommendation = engine.generate_recommendation

        expect(recommendation.action).to eq(:replace_factory_strategy)
        expect(recommendation.confidence).to eq(:medium)
        expect(recommendation.from_value).to eq('create(:user)')
        expect(recommendation.to_value).to eq('build_stubbed(:user)')
        expect(recommendation.spec_location).to eq('spec/models/user_spec.rb:42')
        expect(recommendation.agent_results).to eq(agent_results)
      end
    end

    context 'with high risk factors' do
      let(:high_risk_agent_result) do
        SpecScout::AgentResult.new(
          agent_name: :risk,
          verdict: :high_risk,
          confidence: :high,
          reasoning: 'High risk factors detected',
          metadata: { risk_score: 10 }
        )
      end

      it 'generates no action recommendation due to high risk' do
        agent_results = [db_agent_result, factory_agent_result, high_risk_agent_result]
        engine = described_class.new(agent_results, profile_data)
        recommendation = engine.generate_recommendation

        expect(recommendation.action).to eq(:no_action)
        expect(recommendation.confidence).to eq(:low)
        expect(recommendation.explanation.join(' ')).to include('High risk factors prevent optimization')
      end
    end

    context 'with conflicting agents' do
      let(:db_required_result) do
        SpecScout::AgentResult.new(
          agent_name: :database,
          verdict: :db_required,
          confidence: :high,
          reasoning: 'Database writes detected',
          metadata: {}
        )
      end

      it 'generates soft suggestion for conflicting persistence needs' do
        agent_results = [db_agent_result, db_required_result]
        engine = described_class.new(agent_results, profile_data)
        recommendation = engine.generate_recommendation

        expect(recommendation.action).to eq(:review_test_intent)
        expect(recommendation.confidence).to eq(:low)
        expect(recommendation.explanation.join(' ')).to include('Conflicting agent opinions detected')
      end
    end

    context 'with unclear signals' do
      let(:unclear_agent_result) do
        SpecScout::AgentResult.new(
          agent_name: :intent,
          verdict: :intent_unclear,
          confidence: :low,
          reasoning: 'Mixed behavioral signals',
          metadata: {}
        )
      end

      it 'generates no action recommendation for unclear signals' do
        agent_results = [unclear_agent_result]
        engine = described_class.new(agent_results, profile_data)
        recommendation = engine.generate_recommendation

        expect(recommendation.action).to eq(:no_action)
        expect(recommendation.confidence).to eq(:low)
        expect(recommendation.explanation).to include('No clear consensus among agents')
      end
    end
  end

  describe 'decision matrix logic' do
    it 'applies ≥2 agents agree rule for strong recommendations' do
      agent_results = [db_agent_result, factory_agent_result]
      engine = described_class.new(agent_results, profile_data)
      recommendation = engine.generate_recommendation

      expect(recommendation.action).to eq(:replace_factory_strategy)
      expect(%i[medium high]).to include(recommendation.confidence)
    end

    it 'downgrades confidence when risk agents flag issues' do
      potential_risk_result = SpecScout::AgentResult.new(
        agent_name: :risk,
        verdict: :potential_side_effects,
        confidence: :medium,
        reasoning: 'Some risk indicators detected',
        metadata: { risk_score: 3 }
      )

      agent_results = [db_agent_result, factory_agent_result, potential_risk_result]
      engine = described_class.new(agent_results, profile_data)
      recommendation = engine.generate_recommendation

      # Should still recommend optimization but with downgraded confidence
      expect(recommendation.action).to eq(:avoid_db_persistence)
      expect(recommendation.confidence).to eq(:medium) # Downgraded from potential high
    end

    it 'generates soft suggestions for conflicting agents' do
      conflicting_db_result = SpecScout::AgentResult.new(
        agent_name: :database,
        verdict: :db_required,
        confidence: :high,
        reasoning: 'Database persistence required',
        metadata: {}
      )

      agent_results = [db_agent_result, conflicting_db_result]
      engine = described_class.new(agent_results, profile_data)
      recommendation = engine.generate_recommendation

      expect(recommendation.action).to eq(:review_test_intent)
      expect(recommendation.explanation.join(' ')).to include('persistence requirements')
    end

    it 'recommends no action for unclear signals' do
      unclear_results = [
        SpecScout::AgentResult.new(
          agent_name: :intent,
          verdict: :intent_unclear,
          confidence: :low,
          reasoning: 'Unclear intent',
          metadata: {}
        )
      ]

      engine = described_class.new(unclear_results, profile_data)
      recommendation = engine.generate_recommendation

      expect(recommendation.action).to eq(:no_action)
      expect(recommendation.explanation).to include('No clear consensus among agents')
    end
  end

  describe 'confidence calculation' do
    it 'calculates high confidence for strong agreement with multiple high-confidence agents' do
      high_conf_db = db_agent_result.dup.tap { |r| r.confidence = :high }
      high_conf_factory = factory_agent_result.dup.tap { |r| r.confidence = :high }
      high_conf_risk = risk_agent_result.dup.tap { |r| r.confidence = :high }

      agent_results = [high_conf_db, high_conf_factory, high_conf_risk]
      engine = described_class.new(agent_results, profile_data)
      recommendation = engine.generate_recommendation

      expect(%i[high medium]).to include(recommendation.confidence)
    end

    it 'applies risk-based confidence downgrading' do
      high_risk_result = SpecScout::AgentResult.new(
        agent_name: :risk,
        verdict: :high_risk,
        confidence: :high,
        reasoning: 'High risk detected',
        metadata: { risk_score: 8 }
      )

      agent_results = [db_agent_result, factory_agent_result, high_risk_result]
      engine = described_class.new(agent_results, profile_data)
      recommendation = engine.generate_recommendation

      expect(recommendation.confidence).to eq(:low) # Forced low due to high risk
    end
  end

  describe 'explanation building' do
    it 'includes agent summary in explanation' do
      agent_results = [db_agent_result, factory_agent_result, risk_agent_result]
      engine = described_class.new(agent_results, profile_data)
      recommendation = engine.generate_recommendation

      expect(recommendation.explanation).to include('Analyzed 3 agent(s): 2 high confidence, 1 medium confidence, 0 low confidence')
    end

    it 'includes consensus analysis in explanation' do
      agent_results = [db_agent_result, factory_agent_result]
      engine = described_class.new(agent_results, profile_data)
      recommendation = engine.generate_recommendation

      expect(recommendation.explanation).to include('2 agent(s) agree on optimize_persistence approach')
    end

    it 'includes risk factors when present' do
      risk_result = SpecScout::AgentResult.new(
        agent_name: :risk,
        verdict: :potential_side_effects,
        confidence: :medium,
        reasoning: 'Some risk factors',
        metadata: { risk_score: 3, total_risk_factors: 2 }
      )

      agent_results = [db_agent_result, risk_result]
      engine = described_class.new(agent_results, profile_data)
      recommendation = engine.generate_recommendation

      expect(recommendation.explanation.join(' ')).to include('Risk factors detected')
    end
  end
end
