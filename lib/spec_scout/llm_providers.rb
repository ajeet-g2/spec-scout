# frozen_string_literal: true

require_relative 'llm_providers/base_llm_provider'
require_relative 'llm_providers/openai/config'
require_relative 'llm_providers/anthropic/config'
require_relative 'llm_providers/local/config'
require_relative 'llm_providers/openai/client'
require_relative 'llm_providers/anthropic/client'
require_relative 'llm_providers/local/client'

module SpecScout
  module LLMProviders
    # Factory method to create LLM providers
    # @param provider_type [Symbol] The type of provider (:openai, :anthropic, :local_llm)
    # @param config [Object] The provider-specific configuration
    # @return [BaseLLMProvider] The configured provider instance
    # @raise [ArgumentError] If provider type is unknown
    def self.create_provider(provider_type, config)
      case provider_type.to_sym
      when :openai
        OpenAIProvider.new(config)
      when :anthropic
        AnthropicProvider.new(config)
      when :local_llm, :local
        LocalLLMProvider.new(config)
      else
        raise ArgumentError,
              "Unknown LLM provider: #{provider_type}. Supported providers: :openai, :anthropic, :local_llm"
      end
    end

    # Get list of available provider types
    # @return [Array<Symbol>] Available provider types
    def self.available_providers
      %i[openai anthropic local_llm]
    end

    # Create configuration for a provider type
    # @param provider_type [Symbol] The type of provider
    # @param options [Hash] Configuration options
    # @return [Object] The provider-specific configuration
    # @raise [ArgumentError] If provider type is unknown
    def self.create_config(provider_type, options = {})
      case provider_type.to_sym
      when :openai
        options.empty? ? OpenAIConfig.new : OpenAIConfig.from_hash(options)
      when :anthropic
        options.empty? ? AnthropicConfig.new : AnthropicConfig.from_hash(options)
      when :local_llm, :local
        options.empty? ? LocalLLMConfig.new : LocalLLMConfig.from_hash(options)
      else
        raise ArgumentError,
              "Unknown LLM provider: #{provider_type}. Supported providers: :openai, :anthropic, :local_llm"
      end
    end

    # Check if a provider type is supported
    # @param provider_type [Symbol] The provider type to check
    # @return [Boolean] True if the provider is supported
    def self.supported_provider?(provider_type)
      available_providers.include?(provider_type.to_sym)
    end
  end
end
