# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SpecScout::OptimizerResult do
  describe '#initialize' do
    it 'creates a valid OptimizerResult with default values' do
      result = described_class.new

      expect(result.optimizer_name).to eq(:unknown)
      expect(result.verdict).to eq(:no_verdict)
      expect(result.confidence).to eq(:low)
      expect(result.reasoning).to eq('')
      expect(result.metadata).to eq({})
    end

    it 'creates an OptimizerResult with provided values' do
      result = described_class.new(
        optimizer_name: :database,
        verdict: :db_unnecessary,
        confidence: :high,
        reasoning: 'No database operations detected',
        metadata: { query_count: 0 }
      )

      expect(result.optimizer_name).to eq(:database)
      expect(result.verdict).to eq(:db_unnecessary)
      expect(result.confidence).to eq(:high)
      expect(result.reasoning).to eq('No database operations detected')
      expect(result.metadata).to eq({ query_count: 0 })
    end
  end

  describe '#valid?' do
    it 'returns true for valid OptimizerResult' do
      result = described_class.new(
        optimizer_name: :database,
        verdict: :db_unnecessary,
        confidence: :high,
        reasoning: 'Test reasoning',
        metadata: {}
      )

      expect(result.valid?).to be true
    end

    it 'returns false for invalid confidence level' do
      result = described_class.new(confidence: :invalid)

      expect(result.valid?).to be false
    end
  end

  describe 'confidence level helpers' do
    it 'correctly identifies high confidence' do
      result = described_class.new(confidence: :high)
      expect(result.high_confidence?).to be true
      expect(result.medium_confidence?).to be false
      expect(result.low_confidence?).to be false
    end

    it 'correctly identifies medium confidence' do
      result = described_class.new(confidence: :medium)
      expect(result.high_confidence?).to be false
      expect(result.medium_confidence?).to be true
      expect(result.low_confidence?).to be false
    end

    it 'correctly identifies low confidence' do
      result = described_class.new(confidence: :low)
      expect(result.high_confidence?).to be false
      expect(result.medium_confidence?).to be false
      expect(result.low_confidence?).to be true
    end
  end
end
