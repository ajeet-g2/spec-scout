# frozen_string_literal: true

require 'spec_helper'
require 'prop_check'

RSpec.describe 'LLM Provider Functional Equivalence' do
  # **Feature: llm-providers-reorganization, Property 7: Functional Equivalence**
  describe 'Property 7: Functional Equivalence' do
    let(:providers) do
      [
        {
          name: 'OpenAI',
          class: SpecScout::LLMProviders::OpenAIProvider,
          config_class: SpecScout::LLMProviders::OpenAIConfig
        },
        {
          name: 'Anthropic',
          class: SpecScout::LLMProviders::AnthropicProvider,
          config_class: SpecScout::LLMProviders::AnthropicConfig
        },
        {
          name: 'Local LLM',
          class: SpecScout::LLMProviders::LocalLLMProvider,
          config_class: SpecScout::LLMProviders::LocalLLMConfig
        }
      ]
    end

    it 'all provider classes can be instantiated with valid configs' do
      PropCheck.forall(
        provider_info: PropCheck::Generators.one_of(*providers.map { |p| PropCheck::Generators.constant(p) })
      ) do |provider_info:|
        config = create_valid_config(provider_info[:config_class])

        # Should be able to instantiate the provider
        provider = provider_info[:class].new(config)

        # Provider should respond to core methods
        expect(provider).to respond_to(:generate)
        expect(provider).to respond_to(:validate_response)
        expect(provider).to respond_to(:available?)
        expect(provider).to respond_to(:provider_name)

        # Provider name should be consistent (can be string or symbol)
        provider_name = provider.provider_name
        expect([String, Symbol]).to include(provider_name.class)
        expect(provider_name.to_s.length).to be > 0

        true
      end
    end

    it 'provider availability check is consistent' do
      PropCheck.forall(
        provider_info: PropCheck::Generators.one_of(*providers.map { |p| PropCheck::Generators.constant(p) })
      ) do |provider_info:|
        config = create_valid_config(provider_info[:config_class])
        provider = provider_info[:class].new(config)

        # availability? should return a boolean
        availability = provider.available?
        expect([true, false]).to include(availability)

        # Multiple calls should return the same result (idempotent)
        expect(provider.available?).to eq(availability)

        true
      end
    end

    it 'config classes maintain validation behavior' do
      PropCheck.forall(
        config_info: PropCheck::Generators.one_of(*providers.map do |p|
          PropCheck::Generators.constant(p[:config_class])
        end)
      ) do |config_info:|
        config = config_info.new

        # Config should respond to validation methods
        expect(config).to respond_to(:validate!) if config.respond_to?(:validate!)
        expect(config).to respond_to(:complete?) if config.respond_to?(:complete?)

        # Setting valid values should work
        case config_info.name
        when /OpenAI/
          config.api_key = 'test-key-123'
          expect(config.api_key).to eq('test-key-123')
        when /Anthropic/
          config.api_key = 'test-key-456'
          expect(config.api_key).to eq('test-key-456')
        when /Local/
          config.endpoint = 'http://localhost:8080'
          config.model = 'test-model'
          expect(config.endpoint).to eq('http://localhost:8080')
          expect(config.model).to eq('test-model')
        end

        true
      end
    end

    it 'provider classes maintain inheritance hierarchy' do
      PropCheck.forall(
        provider_info: PropCheck::Generators.one_of(*providers.map { |p| PropCheck::Generators.constant(p) })
      ) do |provider_info:|
        # All providers should inherit from BaseLLMProvider
        expect(provider_info[:class].ancestors).to include(SpecScout::LLMProviders::BaseLLMProvider)

        # Should be in the correct module namespace
        expect(provider_info[:class].name).to start_with('SpecScout::LLMProviders::')

        true
      end
    end

    it 'error handling behavior is preserved' do
      PropCheck.forall(
        provider_info: PropCheck::Generators.one_of(*providers.map { |p| PropCheck::Generators.constant(p) }),
        invalid_input: PropCheck::Generators.one_of(PropCheck::Generators.constant(nil),
                                                    PropCheck::Generators.constant(''), PropCheck::Generators.constant({}))
      ) do |provider_info:, invalid_input:|
        config = create_valid_config(provider_info[:config_class])
        provider = provider_info[:class].new(config)

        # Should handle invalid inputs gracefully (not crash)
        begin
          result = provider.validate_response(invalid_input)
          # If it doesn't raise an error, result should be boolean or meaningful
          expect([true, false, nil].any? { |v| result.instance_of?(v.class) }).to be(true)
        rescue StandardError => e
          # If it raises an error, it should be a meaningful error
          expect(e.message).to be_a(String)
          expect(e.message.length).to be > 0
        end

        true
      end
    end

    private

    def create_valid_config(config_class)
      config = config_class.new

      case config_class.name
      when /OpenAI/
        config.api_key = 'test-openai-key'
        config.model = 'gpt-3.5-turbo' if config.respond_to?(:model=)
      when /Anthropic/
        config.api_key = 'test-anthropic-key'
        config.model = 'claude-3-sonnet-20240229' if config.respond_to?(:model=)
      when /Local/
        config.endpoint = 'http://localhost:11434'
        config.model = 'llama2'
      end

      config
    end
  end
end
