# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module SpecScout
  module LLMProviders
    # OpenAI provider implementation for LLM integration
    class OpenAIProvider < BaseLLMProvider
      API_BASE_URL = 'https://api.openai.com/v1'
      CHAT_COMPLETIONS_ENDPOINT = '/chat/completions'

      def initialize(config)
        @config = config
        validate_config(@config, %i[api_key model])
        @config.validate!
      end

      # Generate a response using OpenAI's chat completions API
      # @param prompt_template [String] The prompt template with placeholders
      # @param context [Hash] Context data to substitute into the template
      # @param system_prompt [String, nil] Optional system prompt
      # @return [String] The generated response
      def generate(prompt_template, context, system_prompt = nil)
        prompt = render_template(prompt_template, context)

        messages = []
        messages << { role: 'system', content: system_prompt } if system_prompt
        messages << { role: 'user', content: prompt }

        request_body = {
          model: @config.model,
          messages: messages,
          temperature: @config.temperature,
          max_tokens: @config.max_tokens
        }

        response = make_api_request(CHAT_COMPLETIONS_ENDPOINT, request_body)
        extract_content_from_response(response)
      rescue StandardError => e
        handle_api_error(e)
      end

      # Validate that the response is properly formatted JSON
      # @param response [String] The response to validate
      # @return [Boolean] True if the response appears to be valid
      def validate_response(response)
        return false if response.nil? || response.empty?
        return false if response.start_with?('Error communicating with')

        # Try to parse as JSON to validate structure
        JSON.parse(response)
        true
      rescue JSON::ParserError
        # Response might be valid text that's not JSON
        # For now, accept non-empty responses that don't start with error messages
        !response.strip.empty?
      end

      # Check if the provider is available and properly configured
      # @return [Boolean] True if the provider is ready to use
      def available?
        @config.complete? && api_key_valid?
      rescue StandardError
        false
      end

      # Get the provider name
      # @return [Symbol] The provider identifier
      def provider_name
        :openai
      end

      private

      # Make an HTTP request to the OpenAI API
      # @param endpoint [String] The API endpoint path
      # @param body [Hash] The request body
      # @return [Hash] The parsed response
      def make_api_request(endpoint, body)
        uri = URI("#{API_BASE_URL}#{endpoint}")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = @config.timeout
        http.open_timeout = @config.timeout

        request = Net::HTTP::Post.new(uri)
        request['Authorization'] = "Bearer #{@config.api_key}"
        request['Content-Type'] = 'application/json'
        request.body = JSON.generate(body)

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          raise Net::HTTPError.new("HTTP #{response.code}: #{response.message}", response)
        end

        JSON.parse(response.body)
      end

      # Extract the content from the OpenAI API response
      # @param response [Hash] The parsed API response
      # @return [String] The generated content
      def extract_content_from_response(response)
        choices = response['choices']
        raise ArgumentError, 'No choices in response' if choices.nil? || choices.empty?

        message = choices.first['message']
        raise ArgumentError, 'No message in choice' if message.nil?

        content = message['content']
        raise ArgumentError, 'No content in message' if content.nil?

        content.strip
      end

      # Check if the API key is valid by making a simple request
      # @return [Boolean] True if the API key works
      def api_key_valid?
        # Make a minimal request to validate the API key
        request_body = {
          model: @config.model,
          messages: [{ role: 'user', content: 'test' }],
          max_tokens: 1
        }

        make_api_request(CHAT_COMPLETIONS_ENDPOINT, request_body)
        true
      rescue StandardError
        false
      end
    end
  end
end
