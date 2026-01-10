# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SpecScout::LLMProviders do
  describe '.create_provider' do
    let(:openai_config) { SpecScout::LLMProviders::OpenAIConfig.new }
    let(:anthropic_config) { SpecScout::LLMProviders::AnthropicConfig.new }
    let(:local_config) { SpecScout::LLMProviders::LocalLLMConfig.new }

    before do
      openai_config.api_key = 'test-key'
      anthropic_config.api_key = 'test-key'
    end

    it 'creates OpenAI provider' do
      provider = described_class.create_provider(:openai, openai_config)
      expect(provider).to be_a(SpecScout::LLMProviders::OpenAIProvider)
    end

    it 'creates Anthropic provider' do
      provider = described_class.create_provider(:anthropic, anthropic_config)
      expect(provider).to be_a(SpecScout::LLMProviders::AnthropicProvider)
    end

    it 'creates Local LLM provider with :local_llm' do
      provider = described_class.create_provider(:local_llm, local_config)
      expect(provider).to be_a(SpecScout::LLMProviders::LocalLLMProvider)
    end

    it 'creates Local LLM provider with :local' do
      provider = described_class.create_provider(:local, local_config)
      expect(provider).to be_a(SpecScout::LLMProviders::LocalLLMProvider)
    end

    it 'raises error for unknown provider' do
      expect { described_class.create_provider(:unknown, openai_config) }
        .to raise_error(ArgumentError, /Unknown LLM provider: unknown/)
    end
  end

  describe '.available_providers' do
    it 'returns list of available providers' do
      providers = described_class.available_providers
      expect(providers).to contain_exactly(:openai, :anthropic, :local_llm)
    end
  end

  describe '.create_config' do
    it 'creates OpenAI config' do
      config = described_class.create_config(:openai)
      expect(config).to be_a(SpecScout::LLMProviders::OpenAIConfig)
    end

    it 'creates Anthropic config' do
      config = described_class.create_config(:anthropic)
      expect(config).to be_a(SpecScout::LLMProviders::AnthropicConfig)
    end

    it 'creates Local LLM config' do
      config = described_class.create_config(:local_llm)
      expect(config).to be_a(SpecScout::LLMProviders::LocalLLMConfig)
    end

    it 'creates config from hash options' do
      options = { api_key: 'test-key', model: 'custom-model' }
      config = described_class.create_config(:openai, options)

      expect(config.api_key).to eq('test-key')
      expect(config.model).to eq('custom-model')
    end

    it 'raises error for unknown provider' do
      expect { described_class.create_config(:unknown) }
        .to raise_error(ArgumentError, /Unknown LLM provider: unknown/)
    end
  end

  describe '.supported_provider?' do
    it 'returns true for supported providers' do
      expect(described_class.supported_provider?(:openai)).to be true
      expect(described_class.supported_provider?(:anthropic)).to be true
      expect(described_class.supported_provider?(:local_llm)).to be true
    end

    it 'returns false for unsupported providers' do
      expect(described_class.supported_provider?(:unknown)).to be false
    end

    it 'handles string provider names' do
      expect(described_class.supported_provider?('openai')).to be true
    end
  end
end
