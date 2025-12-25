# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SpecScout::Agents::RiskAgent do
  let(:profile_data) do
    SpecScout::ProfileData.new(
      example_location: 'spec/models/user_spec.rb:42',
      spec_type: :model,
      runtime_ms: runtime_ms,
      factories: factory_data,
      db: db_data,
      events: events_data,
      metadata: metadata
    )
  end

  let(:runtime_ms) { 38 }
  let(:factory_data) { {} }
  let(:db_data) { {} }
  let(:events_data) { {} }
  let(:metadata) { {} }

  describe '#evaluate' do
    context 'when no risk factors are present' do
      it 'returns safe to optimize with high confidence' do
        agent = described_class.new(profile_data)
        result = agent.evaluate

        expect(result.verdict).to eq(:safe_to_optimize)
        expect(result.confidence).to eq(:high)
        expect(result.reasoning).to include('No risk factors detected')
        expect(result.metadata[:risk_score]).to eq(0)
        expect(result.metadata[:total_risk_factors]).to eq(0)
      end
    end

    context 'when after_commit callbacks are detected in events' do
      let(:events_data) { { 'after_commit' => { count: 2 }, 'sql.active_record' => { count: 5 } } }

      it 'flags potential side effects with medium confidence' do
        agent = described_class.new(profile_data)
        result = agent.evaluate

        expect(result.verdict).to eq(:potential_side_effects)
        expect(result.confidence).to eq(:medium)
        expect(result.reasoning).to include('Potential side effects detected')
        expect(result.metadata[:callback_indicators]).not_to be_empty
        expect(result.metadata[:callback_indicators].first[:type]).to eq(:event_pattern)
      end
    end

    context 'when callback metadata is present' do
      let(:metadata) { { callbacks: true, after_commit: ['User#send_welcome_email'] } }

      it 'detects callback indicators and flags risk' do
        agent = described_class.new(profile_data)
        result = agent.evaluate

        expect(result.verdict).to eq(:potential_side_effects)
        expect(result.confidence).to eq(:medium)
        expect(result.reasoning).to include('Potential side effects detected')
        expect(result.metadata[:callback_indicators].size).to eq(2)
        expect(result.metadata[:callback_indicators]).to include(
          hash_including(type: :metadata_key, key: :callbacks)
        )
      end
    end

    context 'when high database write activity is detected' do
      let(:db_data) { { inserts: 6, updates: 2, deletes: 1, total_queries: 15 } }

      it 'flags potential side effects due to high database activity' do
        agent = described_class.new(profile_data)
        result = agent.evaluate

        expect(result.verdict).to eq(:potential_side_effects)
        expect(result.confidence).to eq(:medium)
        expect(result.reasoning).to include('Potential side effects detected')
        expect(result.metadata[:side_effect_indicators]).to include(
          hash_including(type: :high_db_writes, count: 9)
        )
      end
    end

    context 'when multiple create factories are used' do
      let(:factory_data) do
        {
          user: { strategy: :create, count: 2 },
          post: { strategy: :create, count: 2 },
          comment: { strategy: :create, count: 1 }
        }
      end

      it 'detects potential side effects from complex factory usage' do
        agent = described_class.new(profile_data)
        result = agent.evaluate

        expect(result.verdict).to eq(:potential_side_effects)
        expect(result.confidence).to eq(:medium)
        expect(result.reasoning).to include('Potential side effects detected')
        expect(result.metadata[:side_effect_indicators]).to include(
          hash_including(type: :multiple_create_factories, count: 5)
        )
      end
    end

    context 'when long runtime is detected' do
      let(:runtime_ms) { 750 }

      it 'flags potential side effects due to long execution time' do
        agent = described_class.new(profile_data)
        result = agent.evaluate

        expect(result.verdict).to eq(:potential_side_effects)
        expect(result.confidence).to eq(:medium)
        expect(result.reasoning).to include('Potential side effects detected')
        expect(result.metadata[:side_effect_indicators]).to include(
          hash_including(type: :long_runtime, runtime_ms: 750)
        )
      end
    end

    context 'when risky factory traits are detected' do
      let(:factory_data) do
        {
          user: {
            strategy: :create,
            count: 1,
            traits: [:with_callback, :published, :activated]
          }
        }
      end

      it 'detects factory risk patterns' do
        agent = described_class.new(profile_data)
        result = agent.evaluate

        expect(result.verdict).to eq(:potential_side_effects)
        expect(result.confidence).to eq(:medium)
        expect(result.reasoning).to include('Potential side effects detected')
        expect(result.metadata[:factory_risk_indicators].size).to eq(3)
        expect(result.metadata[:factory_risk_indicators]).to include(
          hash_including(type: :risky_factory_trait, factory: :user, trait: :with_callback)
        )
      end
    end

    context 'when complex associations are detected' do
      let(:factory_data) do
        {
          user: {
            strategy: :create,
            count: 1,
            associations: [:posts, :comments, :profile, :settings]
          }
        }
      end

      it 'flags complex association patterns as risk factors' do
        agent = described_class.new(profile_data)
        result = agent.evaluate

        expect(result.verdict).to eq(:potential_side_effects)
        expect(result.confidence).to eq(:low)
        expect(result.reasoning).to include('Minor risk indicators detected')
        expect(result.metadata[:factory_risk_indicators]).to include(
          hash_including(type: :complex_associations, factory: :user, associations_count: 4)
        )
      end
    end

    context 'when multiple event types suggest callback chains' do
      let(:events_data) do
        {
          'after_create' => { count: 1 },
          'after_update' => { count: 2 },
          'mailer.deliver' => { count: 1 },
          'job.enqueue' => { count: 1 }
        }
      end

      it 'detects complex callback chain indicators' do
        agent = described_class.new(profile_data)
        result = agent.evaluate

        expect(result.verdict).to eq(:high_risk)
        expect(result.confidence).to eq(:high)
        expect(result.reasoning).to include('High risk optimization scenario detected')
        expect(result.metadata[:complex_chain_indicators]).to include(
          hash_including(type: :multiple_events, count: 4)
        )
        expect(result.metadata[:callback_indicators].size).to be >= 2
      end
    end

    context 'when high risk score is calculated' do
      let(:events_data) { { 'after_commit' => { count: 2 }, 'after_create' => { count: 1 } } }
      let(:metadata) { { callbacks: true, mailers: ['WelcomeMailer'] } }
      let(:db_data) { { inserts: 8, updates: 3, total_queries: 15 } }

      it 'returns high risk verdict with high confidence' do
        agent = described_class.new(profile_data)
        result = agent.evaluate

        expect(result.verdict).to eq(:high_risk)
        expect(result.confidence).to eq(:high)
        expect(result.reasoning).to include('High risk optimization scenario detected')
        expect(result.metadata[:risk_score]).to be >= 6
        expect(result.metadata[:total_risk_factors]).to be >= 4
      end
    end

    context 'when nested operations are indicated in metadata' do
      let(:metadata) { { nested_operations: true, chained_callbacks: ['User', 'Profile', 'Notification'] } }

      it 'detects complex callback chain indicators' do
        agent = described_class.new(profile_data)
        result = agent.evaluate

        expect(result.verdict).to eq(:potential_side_effects)
        expect(result.confidence).to eq(:medium)
        expect(result.reasoning).to include('Potential side effects detected')
        expect(result.metadata[:complex_chain_indicators]).to include(
          hash_including(type: :nested_operations)
        )
      end
    end
  end

  describe '#agent_name' do
    it 'returns :risk' do
      agent = described_class.new(profile_data)
      expect(agent.agent_name).to eq(:risk)
    end
  end
end