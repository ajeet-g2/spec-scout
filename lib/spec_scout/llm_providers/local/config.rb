# frozen_string_literal: true

module SpecScout
  module LLMProviders
    # Configuration class for local LLM provider
    class LocalLLMConfig
      attr_accessor :endpoint, :model, :temperature, :max_tokens, :timeout, :headers

      DEFAULT_ENDPOINT = 'http://localhost:11434'
      DEFAULT_MODEL = 'codellama'
      DEFAULT_TEMPERATURE = 0.1
      DEFAULT_MAX_TOKENS = 1000
      DEFAULT_TIMEOUT = 60 # Local models may be slower

      def initialize
        @endpoint = ENV['LOCAL_LLM_ENDPOINT'] || DEFAULT_ENDPOINT
        @model = ENV['LOCAL_LLM_MODEL'] || DEFAULT_MODEL
        @temperature = DEFAULT_TEMPERATURE
        @max_tokens = DEFAULT_MAX_TOKENS
        @timeout = DEFAULT_TIMEOUT
        @headers = {}
      end

      # Validate the configuration
      # @return [Boolean] True if configuration is valid
      # @raise [ArgumentError] If configuration is invalid
      def validate!
        raise ArgumentError, 'Endpoint must be specified' if endpoint.nil? || endpoint.empty?
        raise ArgumentError, 'Model must be specified' if model.nil? || model.empty?
        raise ArgumentError, 'Temperature must be between 0 and 2' unless temperature.between?(0, 2)
        raise ArgumentError, 'Max tokens must be positive' unless max_tokens.positive?
        raise ArgumentError, 'Timeout must be positive' unless timeout.positive?

        # Validate endpoint format
        begin
          uri = URI.parse(endpoint)
          unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
            raise ArgumentError, 'Endpoint must be a valid HTTP/HTTPS URL'
          end
        rescue URI::InvalidURIError
          raise ArgumentError, 'Endpoint must be a valid URL'
        end

        true
      end

      # Check if the configuration is complete
      # @return [Boolean] True if all required fields are present
      def complete?
        !endpoint.nil? && !endpoint.empty? && !model.nil? && !model.empty?
      end

      # Convert configuration to hash
      # @return [Hash] Configuration as hash
      def to_h
        {
          endpoint: endpoint,
          model: model,
          temperature: temperature,
          max_tokens: max_tokens,
          timeout: timeout,
          headers: headers
        }
      end

      # Create configuration from hash
      # @param hash [Hash] Configuration hash
      # @return [LocalLLMConfig] New configuration instance
      def self.from_hash(hash)
        config = new
        config.endpoint = hash[:endpoint] || hash['endpoint'] || DEFAULT_ENDPOINT
        config.model = hash[:model] || hash['model'] || DEFAULT_MODEL
        config.temperature = hash[:temperature] || hash['temperature'] || DEFAULT_TEMPERATURE
        config.max_tokens = hash[:max_tokens] || hash['max_tokens'] || DEFAULT_MAX_TOKENS
        config.timeout = hash[:timeout] || hash['timeout'] || DEFAULT_TIMEOUT
        config.headers = hash[:headers] || hash['headers'] || {}
        config
      end

      # Add custom header for authentication or other purposes
      # @param key [String] Header name
      # @param value [String] Header value
      def add_header(key, value)
        @headers[key] = value
      end

      # Remove custom header
      # @param key [String] Header name to remove
      def remove_header(key)
        @headers.delete(key)
      end
    end
  end
end
