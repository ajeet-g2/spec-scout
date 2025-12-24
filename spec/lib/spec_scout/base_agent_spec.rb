# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SpecScout::BaseAgent do
  let(:valid_profile_data) do
    SpecScout::ProfileData.new(
      example_location: 'spec/models/user_spec.rb:42',
      spec_type: :model,
      runtime_ms: 38,
      factories: { user: { strategy: :create, count: 1 } },
      db: { total_queries: 6, inserts: 1, selects: 5 }
    )
  end

  # Create a concrete implementation for testing
  let(:test_agent_class) do
    Class.new(described_class) do
      def evaluate
        create_result(
          verdict: :test_verdict,
          confidence: :high,
          reasoning: 'Test reasoning'
        )
      end
    end
  end

  describe '#initialize' do
    it 'accepts valid ProfileData' do
      agent = test_agent_class.new(valid_profile_data)
      expect(agent.profile_data).to eq(valid_profile_data)
    end

    it 'raises error for invalid ProfileData' do
      expect { test_agent_class.new('invalid') }.to raise_error(ArgumentError, /Expected ProfileData/)
    end

    it 'raises error for invalid ProfileData structure' do
      invalid_profile = SpecScout::ProfileData.new
      invalid_profile.example_location = nil

      expect { test_agent_class.new(invalid_profile) }.to raise_error(ArgumentError, /Invalid ProfileData structure/)
    end
  end

  describe '#evaluate' do
    it 'raises NotImplementedError for base class' do
      agent = described_class.new(valid_profile_data)
      expect { agent.evaluate }.to raise_error(NotImplementedError, /Subclasses must implement #evaluate/)
    end

    it 'returns AgentResult for concrete implementation' do
      agent = test_agent_class.new(valid_profile_data)
      result = agent.evaluate

      expect(result).to be_a(SpecScout::AgentResult)
      expect(result.verdict).to eq(:test_verdict)
      expect(result.confidence).to eq(:high)
      expect(result.reasoning).to eq('Test reasoning')
    end
  end

  describe '#agent_name' do
    it 'derives agent name from class name' do
      agent = test_agent_class.new(valid_profile_data)
      # The test class doesn't have "Agent" in the name, so it returns the full class name
      expect(agent.agent_name).to be_a(Symbol)
    end
  end

  describe 'protected helper methods' do
    let(:agent) { test_agent_class.new(valid_profile_data) }

    describe '#create_result' do
      it 'creates valid AgentResult' do
        result = agent.send(:create_result,
                            verdict: :test_verdict,
                            confidence: :medium,
                            reasoning: 'Test reasoning',
                            metadata: { test: true })

        expect(result).to be_a(SpecScout::AgentResult)
        expect(result.verdict).to eq(:test_verdict)
        expect(result.confidence).to eq(:medium)
        expect(result.reasoning).to eq('Test reasoning')
        expect(result.metadata).to eq({ test: true })
      end
    end

    describe '#database_operations_present?' do
      it 'returns true when database operations are present' do
        expect(agent.send(:database_operations_present?)).to be true
      end

      it 'returns false when no database operations' do
        profile_data = SpecScout::ProfileData.new(db: {})
        agent = test_agent_class.new(profile_data)
        expect(agent.send(:database_operations_present?)).to be false
      end
    end

    describe '#factories_present?' do
      it 'returns true when factories are present' do
        expect(agent.send(:factories_present?)).to be true
      end

      it 'returns false when no factories' do
        profile_data = SpecScout::ProfileData.new(factories: {})
        agent = test_agent_class.new(profile_data)
        expect(agent.send(:factories_present?)).to be false
      end
    end
  end
end
