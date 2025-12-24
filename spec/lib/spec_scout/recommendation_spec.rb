# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SpecScout::Recommendation do
  describe '#initialize' do
    it 'creates a valid Recommendation with default values' do
      recommendation = described_class.new

      expect(recommendation.spec_location).to eq('')
      expect(recommendation.action).to eq(:no_action)
      expect(recommendation.from_value).to eq('')
      expect(recommendation.to_value).to eq('')
      expect(recommendation.confidence).to eq(:low)
      expect(recommendation.explanation).to eq([])
      expect(recommendation.agent_results).to eq([])
    end

    it 'creates a Recommendation with provided values' do
      agent_result = SpecScout::AgentResult.new(
        agent_name: :database,
        verdict: :db_unnecessary,
        confidence: :high,
        reasoning: 'No database operations'
      )

      recommendation = described_class.new(
        spec_location: 'spec/models/user_spec.rb:42',
        action: :replace_factory_strategy,
        from_value: 'create(:user)',
        to_value: 'build_stubbed(:user)',
        confidence: :high,
        explanation: ['Factory can use build_stubbed'],
        agent_results: [agent_result]
      )

      expect(recommendation.spec_location).to eq('spec/models/user_spec.rb:42')
      expect(recommendation.action).to eq(:replace_factory_strategy)
      expect(recommendation.from_value).to eq('create(:user)')
      expect(recommendation.to_value).to eq('build_stubbed(:user)')
      expect(recommendation.confidence).to eq(:high)
      expect(recommendation.explanation).to eq(['Factory can use build_stubbed'])
      expect(recommendation.agent_results).to eq([agent_result])
    end
  end

  describe '#valid?' do
    it 'returns true for valid Recommendation' do
      agent_result = SpecScout::AgentResult.new
      recommendation = described_class.new(
        spec_location: 'spec/models/user_spec.rb:42',
        action: :replace_factory_strategy,
        confidence: :high,
        explanation: ['Test explanation'],
        agent_results: [agent_result]
      )

      expect(recommendation.valid?).to be true
    end

    it 'returns false for invalid action' do
      recommendation = described_class.new(action: :invalid_action)

      expect(recommendation.valid?).to be false
    end

    it 'returns false for invalid agent results' do
      recommendation = described_class.new(agent_results: ['not an agent result'])

      expect(recommendation.valid?).to be false
    end
  end

  describe '#actionable?' do
    it 'returns true for actionable recommendations' do
      recommendation = described_class.new(action: :replace_factory_strategy)
      expect(recommendation.actionable?).to be true
    end

    it 'returns false for no_action recommendations' do
      recommendation = described_class.new(action: :no_action)
      expect(recommendation.actionable?).to be false
    end
  end

  describe 'confidence level helpers' do
    it 'correctly identifies confidence levels' do
      high_rec = described_class.new(confidence: :high)
      medium_rec = described_class.new(confidence: :medium)
      low_rec = described_class.new(confidence: :low)

      expect(high_rec.high_confidence?).to be true
      expect(medium_rec.medium_confidence?).to be true
      expect(low_rec.low_confidence?).to be true
    end
  end
end
