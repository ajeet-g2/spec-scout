# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SpecScout::Agents::DatabaseAgent do
  let(:profile_data) do
    SpecScout::ProfileData.new(
      example_location: 'spec/models/user_spec.rb:42',
      spec_type: :model,
      runtime_ms: 38,
      factories: { user: { strategy: :create, count: 1 } },
      db: db_data,
      events: {},
      metadata: {}
    )
  end

  describe '#evaluate' do
    context 'when no database operations are present' do
      let(:db_data) { {} }

      it 'returns unclear verdict with low confidence' do
        agent = described_class.new(profile_data)
        result = agent.evaluate

        expect(result.verdict).to eq(:db_unclear)
        expect(result.confidence).to eq(:low)
        expect(result.reasoning).to include('No database usage data available')
        expect(result.metadata[:no_data]).to be true
      end
    end

    context 'when no database writes and minimal reads' do
      let(:db_data) { { inserts: 0, selects: 1, total_queries: 1 } }

      it 'recommends avoiding database persistence with high confidence' do
        agent = described_class.new(profile_data)
        result = agent.evaluate

        expect(result.verdict).to eq(:db_unnecessary)
        expect(result.confidence).to eq(:high)
        expect(result.reasoning).to include('No database writes detected and minimal reads')
        expect(result.metadata[:insert_count]).to eq(0)
        expect(result.metadata[:select_count]).to eq(1)
      end
    end

    context 'when no database writes but multiple reads' do
      let(:db_data) { { inserts: 0, selects: 5, total_queries: 5 } }

      it 'suggests database persistence may be unnecessary with medium confidence' do
        agent = described_class.new(profile_data)
        result = agent.evaluate

        expect(result.verdict).to eq(:db_unnecessary)
        expect(result.confidence).to eq(:medium)
        expect(result.reasoning).to include('No database writes detected but 5 reads')
      end
    end

    context 'when database writes are present' do
      let(:db_data) { { inserts: 2, selects: 3, total_queries: 5 } }

      it 'indicates database persistence is required with high confidence' do
        agent = described_class.new(profile_data)
        result = agent.evaluate

        expect(result.verdict).to eq(:db_required)
        expect(result.confidence).to eq(:high)
        expect(result.reasoning).to include('Database writes detected (2 inserts)')
      end
    end
  end

  describe '#agent_name' do
    let(:db_data) { {} }
    let(:factory_data) { {} }

    it 'returns :database' do
      agent = described_class.new(profile_data)
      expect(agent.agent_name).to eq(:database)
    end
  end
end
