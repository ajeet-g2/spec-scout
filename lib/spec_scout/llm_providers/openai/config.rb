# frozen_string_literal: true

module SpecScout
  module LLMProviders
    # Configuration class for OpenAI provider
    class OpenAIConfig
      attr_accessor :api_key, :model, :temperature, :max_tokens, :timeout

      DEFAULT_MODEL = 'gpt-4'
      DEFAULT_TEMPERATURE = 0.1
      DEFAULT_MAX_TOKENS = 1000
      DEFAULT_TIMEOUT = 30

      def initialize
        @api_key = ENV['OPENAI_API_KEY']
        @model = DEFAULT_MODEL
        @temperature = DEFAULT_TEMPERATURE
        @max_tokens = DEFAULT_MAX_TOKENS
        @timeout = DEFAULT_TIMEOUT
      end

      # Validate the configuration
      # @return [Boolean] True if configuration is valid
      # @raise [ArgumentError] If configuration is invalid
      def validate!
        raise ArgumentError, 'OpenAI API key is required' if api_key.nil? || api_key.empty?
        raise ArgumentError, 'Model must be specified' if model.nil? || model.empty?
        raise ArgumentError, 'Temperature must be between 0 and 2' unless temperature.between?(0, 2)
        raise ArgumentError, 'Max tokens must be positive' unless max_tokens.positive?
        raise ArgumentError, 'Timeout must be positive' unless timeout.positive?

        true
      end

      # Check if the configuration is complete
      # @return [Boolean] True if all required fields are present
      def complete?
        !api_key.nil? && !api_key.empty? && !model.nil? && !model.empty?
      end

      # Convert configuration to hash
      # @return [Hash] Configuration as hash
      def to_h
        {
          api_key: api_key,
          model: model,
          temperature: temperature,
          max_tokens: max_tokens,
          timeout: timeout
        }
      end

      # Create configuration from hash
      # @param hash [Hash] Configuration hash
      # @return [OpenAIConfig] New configuration instance
      def self.from_hash(hash)
        config = new
        config.api_key = hash[:api_key] || hash['api_key']
        config.model = hash[:model] || hash['model'] || DEFAULT_MODEL
        config.temperature = hash[:temperature] || hash['temperature'] || DEFAULT_TEMPERATURE
        config.max_tokens = hash[:max_tokens] || hash['max_tokens'] || DEFAULT_MAX_TOKENS
        config.timeout = hash[:timeout] || hash['timeout'] || DEFAULT_TIMEOUT
        config
      end
    end
  end
end
