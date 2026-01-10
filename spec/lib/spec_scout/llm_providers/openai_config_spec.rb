# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SpecScout::LLMProviders::OpenAIConfig do
  let(:config) { described_class.new }

  describe '#initialize' do
    it 'sets default values' do
      expect(config.api_key).to eq(ENV['OPENAI_API_KEY'])
      expect(config.model).to eq('gpt-4')
      expect(config.temperature).to eq(0.1)
      expect(config.max_tokens).to eq(1000)
      expect(config.timeout).to eq(30)
    end
  end

  describe '#validate!' do
    before do
      config.api_key = 'test-key'
    end

    it 'passes with valid configuration' do
      expect { config.validate! }.not_to raise_error
    end

    it 'raises error when api_key is nil' do
      config.api_key = nil
      expect { config.validate! }.to raise_error(ArgumentError, /API key is required/)
    end

    it 'raises error when api_key is empty' do
      config.api_key = ''
      expect { config.validate! }.to raise_error(ArgumentError, /API key is required/)
    end

    it 'raises error when model is nil' do
      config.model = nil
      expect { config.validate! }.to raise_error(ArgumentError, /Model must be specified/)
    end

    it 'raises error when temperature is out of range' do
      config.temperature = 3.0
      expect { config.validate! }.to raise_error(ArgumentError, /Temperature must be between 0 and 2/)
    end

    it 'raises error when max_tokens is not positive' do
      config.max_tokens = 0
      expect { config.validate! }.to raise_error(ArgumentError, /Max tokens must be positive/)
    end

    it 'raises error when timeout is not positive' do
      config.timeout = 0
      expect { config.validate! }.to raise_error(ArgumentError, /Timeout must be positive/)
    end
  end

  describe '#complete?' do
    it 'returns true when api_key and model are present' do
      config.api_key = 'test-key'
      config.model = 'gpt-4'
      expect(config.complete?).to be true
    end

    it 'returns false when api_key is missing' do
      config.api_key = nil
      config.model = 'gpt-4'
      expect(config.complete?).to be false
    end

    it 'returns false when model is missing' do
      config.api_key = 'test-key'
      config.model = nil
      expect(config.complete?).to be false
    end
  end

  describe '#to_h' do
    it 'returns configuration as hash' do
      config.api_key = 'test-key'
      hash = config.to_h

      expect(hash).to include(
        api_key: 'test-key',
        model: 'gpt-4',
        temperature: 0.1,
        max_tokens: 1000,
        timeout: 30
      )
    end
  end

  describe '.from_hash' do
    it 'creates config from hash with symbol keys' do
      hash = {
        api_key: 'test-key',
        model: 'gpt-3.5-turbo',
        temperature: 0.5,
        max_tokens: 500,
        timeout: 60
      }

      config = described_class.from_hash(hash)

      expect(config.api_key).to eq('test-key')
      expect(config.model).to eq('gpt-3.5-turbo')
      expect(config.temperature).to eq(0.5)
      expect(config.max_tokens).to eq(500)
      expect(config.timeout).to eq(60)
    end

    it 'creates config from hash with string keys' do
      hash = {
        'api_key' => 'test-key',
        'model' => 'gpt-3.5-turbo'
      }

      config = described_class.from_hash(hash)

      expect(config.api_key).to eq('test-key')
      expect(config.model).to eq('gpt-3.5-turbo')
    end

    it 'uses defaults for missing values' do
      hash = { api_key: 'test-key' }

      config = described_class.from_hash(hash)

      expect(config.api_key).to eq('test-key')
      expect(config.model).to eq('gpt-4')
      expect(config.temperature).to eq(0.1)
    end
  end
end
