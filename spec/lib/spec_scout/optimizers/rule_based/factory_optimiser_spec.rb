# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SpecScout::Optimizers::RuleBased::FactoryOptimiser do
  let(:profile_data) do
    SpecScout::ProfileData.new(
      example_location: 'spec/models/user_spec.rb:42',
      spec_type: :model,
      runtime_ms: 38,
      factories: factory_data,
      db: db_data,
      events: {},
      metadata: {}
    )
  end

  describe '#evaluate' do
    context 'when no factories are present' do
      let(:factory_data) { {} }
      let(:db_data) { {} }

      it 'returns optimal strategy with low confidence' do
        optimizer = described_class.new(profile_data)
        result = optimizer.evaluate

        expect(result.verdict).to eq(:strategy_optimal)
        expect(result.confidence).to eq(:low)
        expect(result.reasoning).to include('No factory usage data available')
        expect(result.metadata[:no_data]).to be true
      end
    end

    context 'when using create strategy without database writes' do
      let(:factory_data) { { user: { strategy: :create, count: 2 } } }
      let(:db_data) { { inserts: 0, selects: 3, total_queries: 3 } }

      it 'recommends build_stubbed with medium confidence' do
        optimizer = described_class.new(profile_data)
        result = optimizer.evaluate

        expect(result.verdict).to eq(:prefer_build_stubbed)
        expect(result.confidence).to eq(:medium)
        expect(result.reasoning).to include('Using create strategy (2 factories) but no database writes or association access detected')
        expect(result.metadata[:create_count]).to eq(2)
        expect(result.metadata[:database_writes]).to eq(0)
      end
    end

    context 'when using create strategy with database writes' do
      let(:factory_data) { { user: { strategy: :create, count: 1 } } }
      let(:db_data) { { inserts: 1, selects: 2, total_queries: 3 } }

      it 'indicates create is required with medium confidence' do
        optimizer = described_class.new(profile_data)
        result = optimizer.evaluate

        expect(result.verdict).to eq(:create_required)
        expect(result.confidence).to eq(:medium)
        expect(result.reasoning).to include('Using create strategy with database writes (1 inserts)')
      end
    end

    context 'when already using build_stubbed strategy' do
      let(:factory_data) { { user: { strategy: :build_stubbed, count: 3 } } }
      let(:db_data) { { inserts: 0, selects: 0, total_queries: 0 } }

      it 'indicates strategy is optimal with high confidence' do
        optimizer = described_class.new(profile_data)
        result = optimizer.evaluate

        expect(result.verdict).to eq(:strategy_optimal)
        expect(result.confidence).to eq(:high)
        expect(result.reasoning).to include('Already using build_stubbed strategy (3 factories)')
      end
    end

    context 'when using create strategy with association access patterns' do
      let(:factory_data) do
        {
          user: {
            strategy: :create,
            count: 1,
            associations: %i[posts comments],
            traits: [:with_posts]
          }
        }
      end
      let(:db_data) { { inserts: 0, selects: 2, total_queries: 2 } }

      it 'indicates create is required due to associations with medium confidence' do
        optimizer = described_class.new(profile_data)
        result = optimizer.evaluate

        expect(result.verdict).to eq(:create_required)
        expect(result.confidence).to eq(:medium)
        expect(result.reasoning).to include('Using create strategy with association access patterns detected')
        expect(result.metadata[:association_access_detected]).to be true
      end
    end

    context 'when using create strategy with association indicators in attributes' do
      let(:factory_data) do
        {
          user: {
            strategy: :create,
            count: 1,
            attributes: { company_id: 123, department_id: 456 }
          }
        }
      end
      let(:db_data) { { inserts: 0, selects: 1, total_queries: 1 } }

      it 'detects association patterns and recommends create strategy' do
        optimizer = described_class.new(profile_data)
        result = optimizer.evaluate

        expect(result.verdict).to eq(:create_required)
        expect(result.confidence).to eq(:medium)
        expect(result.reasoning).to include('association access patterns detected')
        expect(result.metadata[:association_access_detected]).to be true
      end
    end

    context 'with mixed factory usage' do
      let(:factory_data) do
        {
          user: { strategy: :create, count: 1 },
          post: { strategy: :build_stubbed, count: 2 }
        }
      end
      let(:db_data) { { inserts: 1, selects: 1, total_queries: 2 } }

      it 'indicates create is required due to database writes with medium confidence' do
        optimizer = described_class.new(profile_data)
        result = optimizer.evaluate

        expect(result.verdict).to eq(:create_required)
        expect(result.confidence).to eq(:medium)
        expect(result.reasoning).to include('Using create strategy with database writes (1 inserts)')
      end
    end
  end

  describe '#optimizer_name' do
    let(:factory_data) { {} }
    let(:db_data) { {} }

    it 'returns :factory' do
      optimizer = described_class.new(profile_data)
      expect(optimizer.optimizer_name).to eq(:factory)
    end
  end
end
