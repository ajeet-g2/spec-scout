# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SpecScout::ProfileNormalizer do
  let(:normalizer) { described_class.new }

  describe '#normalize' do
    let(:testprof_data) do
      {
        factory_prof: {
          stats: {
            user: { strategy: :create, count: 2, time: 0.05 },
            post: { strategy: :build, count: 1, time: 0.02 }
          }
        },
        db_queries: {
          total_queries: 5,
          inserts: 2,
          selects: 3,
          updates: 0,
          deletes: 0
        },
        event_prof: {
          events: {
            'sql.active_record': {
              count: 5,
              time: 0.1,
              examples: [
                { sql: 'SELECT * FROM users', time: 0.02 },
                { sql: 'INSERT INTO posts', time: 0.03 }
              ]
            }
          }
        }
      }
    end

    let(:example_context) do
      {
        location: 'spec/models/user_spec.rb:42',
        runtime: 0.038,
        description: 'creates a user'
      }
    end

    it 'creates a valid ProfileData object' do
      result = normalizer.normalize(testprof_data, example_context)

      expect(result).to be_a(SpecScout::ProfileData)
      expect(result.valid?).to be true
    end

    it 'extracts example location correctly' do
      result = normalizer.normalize(testprof_data, example_context)

      expect(result.example_location).to eq('spec/models/user_spec.rb:42')
    end

    it 'infers spec type from location' do
      result = normalizer.normalize(testprof_data, example_context)

      expect(result.spec_type).to eq(:model)
    end

    it 'converts runtime to milliseconds' do
      result = normalizer.normalize(testprof_data, example_context)

      expect(result.runtime_ms).to eq(38.0)
    end

    it 'normalizes factory data correctly' do
      result = normalizer.normalize(testprof_data, example_context)

      expect(result.factories).to eq({
                                       user: { strategy: :create, count: 2, time: 0.05 },
                                       post: { strategy: :build, count: 1, time: 0.02 }
                                     })
    end

    it 'normalizes database data correctly' do
      result = normalizer.normalize(testprof_data, example_context)

      expect(result.db).to eq({
                                total_queries: 5,
                                inserts: 2,
                                selects: 3,
                                updates: 0,
                                deletes: 0
                              })
    end

    it 'normalizes event data correctly' do
      result = normalizer.normalize(testprof_data, example_context)

      expect(result.events).to have_key(:'sql.active_record')
      expect(result.events[:'sql.active_record'][:count]).to eq(5)
      expect(result.events[:'sql.active_record'][:time]).to eq(0.1)
      expect(result.events[:'sql.active_record'][:examples]).to be_an(Array)
    end

    it 'includes metadata' do
      result = normalizer.normalize(testprof_data, example_context)

      expect(result.metadata).to include(:normalized_at)
      expect(result.metadata[:description]).to eq('creates a user')
    end

    context 'with invalid input' do
      it 'raises NormalizationError for non-hash input' do
        expect { normalizer.normalize('invalid') }.to raise_error(
          SpecScout::ProfileNormalizer::NormalizationError,
          /TestProf data must be a Hash/
        )
      end
    end

    context 'with minimal data' do
      let(:minimal_data) { {} }
      let(:minimal_context) { {} }

      it 'creates valid ProfileData with defaults' do
        result = normalizer.normalize(minimal_data, minimal_context)

        expect(result).to be_a(SpecScout::ProfileData)
        expect(result.valid?).to be true
        expect(result.example_location).to eq('')
        expect(result.spec_type).to eq(:unknown)
        expect(result.runtime_ms).to eq(0)
        expect(result.factories).to eq({})
        expect(result.db).to eq({
                                  total_queries: 0,
                                  inserts: 0,
                                  selects: 0,
                                  updates: 0,
                                  deletes: 0
                                })
      end
    end

    context 'with different spec types' do
      it 'infers controller spec type' do
        context = { location: 'spec/controllers/users_controller_spec.rb:10' }
        result = normalizer.normalize({}, context)

        expect(result.spec_type).to eq(:controller)
      end

      it 'infers request spec type' do
        context = { location: 'spec/requests/api/users_spec.rb:5' }
        result = normalizer.normalize({}, context)

        expect(result.spec_type).to eq(:request)
      end

      it 'infers integration spec type' do
        context = { location: 'spec/integration/user_flow_spec.rb:20' }
        result = normalizer.normalize({}, context)

        expect(result.spec_type).to eq(:integration)
      end
    end
  end

  describe '#set_example_context' do
    it 'sets the current example location' do
      normalizer.set_example_context('spec/models/user_spec.rb:50')

      result = normalizer.normalize({}, {})
      expect(result.example_location).to eq('spec/models/user_spec.rb:50')
    end
  end
end
