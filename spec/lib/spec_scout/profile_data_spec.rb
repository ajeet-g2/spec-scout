# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SpecScout::ProfileData do
  describe '#initialize' do
    it 'creates a valid ProfileData with default values' do
      profile_data = described_class.new

      expect(profile_data.example_location).to eq('')
      expect(profile_data.spec_type).to eq(:unknown)
      expect(profile_data.runtime_ms).to eq(0)
      expect(profile_data.factories).to eq({})
      expect(profile_data.db).to eq({})
      expect(profile_data.events).to eq({})
      expect(profile_data.metadata).to eq({})
    end

    it 'creates a ProfileData with provided values' do
      profile_data = described_class.new(
        example_location: 'spec/models/user_spec.rb:42',
        spec_type: :model,
        runtime_ms: 38,
        factories: { user: { strategy: :create, count: 1 } },
        db: { total_queries: 6, inserts: 1, selects: 5 },
        events: { sql: { count: 6 } },
        metadata: { test_type: 'unit' }
      )

      expect(profile_data.example_location).to eq('spec/models/user_spec.rb:42')
      expect(profile_data.spec_type).to eq(:model)
      expect(profile_data.runtime_ms).to eq(38)
      expect(profile_data.factories).to eq({ user: { strategy: :create, count: 1 } })
      expect(profile_data.db).to eq({ total_queries: 6, inserts: 1, selects: 5 })
      expect(profile_data.events).to eq({ sql: { count: 6 } })
      expect(profile_data.metadata).to eq({ test_type: 'unit' })
    end
  end

  describe '#valid?' do
    it 'returns true for valid ProfileData' do
      profile_data = described_class.new(
        example_location: 'spec/models/user_spec.rb:42',
        spec_type: :model,
        runtime_ms: 38,
        factories: {},
        db: {},
        events: {},
        metadata: {}
      )

      expect(profile_data.valid?).to be true
    end

    it 'returns false for invalid ProfileData' do
      profile_data = described_class.new
      profile_data.example_location = nil

      expect(profile_data.valid?).to be false
    end
  end
end
