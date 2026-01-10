# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

module SpecScout
  module LLMProviders
    # Local LLM provider implementation for self-hosted models
    # Supports Ollama and other OpenAI-compatible local endpoints
    class LocalLLMProvider < BaseLLMProvider
      GENERATE_ENDPOINT = '/api/generate'
      CHAT_ENDPOINT = '/api/chat'

      def initialize(config)
        @config = config
        validate_config(@config, %i[endpoint model])
        @config.validate!
      end

      # Generate a response using the local LLM endpoint
      # @param prompt_template [String] The prompt template with placeholders
      # @param context [Hash] Context data to substitute into the template
      # @param system_prompt [String, nil] Optional system prompt
      # @return [String] The generated response
      def generate(prompt_template, context, system_prompt = nil)
        prompt = render_template(prompt_template, context)

        # Try chat endpoint first (more structured), fall back to generate
        if supports_chat_endpoint?
          generate_with_chat_endpoint(prompt, system_prompt)
        else
          generate_with_generate_endpoint(prompt, system_prompt)
        end
      rescue StandardError => e
        handle_api_error(e)
      end

      # Validate that the response is properly formatted
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
        @config.complete? && endpoint_accessible?
      rescue StandardError
        false
      end

      # Get the provider name
      # @return [Symbol] The provider identifier
      def provider_name
        :local_llm
      end

      private

      # Generate response using the chat endpoint (preferred)
      # @param prompt [String] The user prompt
      # @param system_prompt [String, nil] Optional system prompt
      # @return [String] The generated response
      def generate_with_chat_endpoint(prompt, system_prompt = nil)
        messages = []
        messages << { role: 'system', content: system_prompt } if system_prompt
        messages << { role: 'user', content: prompt }

        request_body = {
          model: @config.model,
          messages: messages,
          options: {
            temperature: @config.temperature,
            num_predict: @config.max_tokens
          },
          stream: false
        }

        response = make_api_request(CHAT_ENDPOINT, request_body)
        extract_chat_content(response)
      end

      # Generate response using the generate endpoint (fallback)
      # @param prompt [String] The user prompt
      # @param system_prompt [String, nil] Optional system prompt
      # @return [String] The generated response
      def generate_with_generate_endpoint(prompt, system_prompt = nil)
        full_prompt = system_prompt ? "#{system_prompt}\n\n#{prompt}" : prompt

        request_body = {
          model: @config.model,
          prompt: full_prompt,
          options: {
            temperature: @config.temperature,
            num_predict: @config.max_tokens
          },
          stream: false
        }

        response = make_api_request(GENERATE_ENDPOINT, request_body)
        extract_generate_content(response)
      end

      # Make an HTTP request to the local LLM endpoint
      # @param endpoint [String] The API endpoint path
      # @param body [Hash] The request body
      # @return [Hash] The parsed response
      def make_api_request(endpoint, body)
        uri = URI("#{@config.endpoint}#{endpoint}")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.read_timeout = @config.timeout
        http.open_timeout = @config.timeout

        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'

        # Add custom headers if configured
        @config.headers.each do |key, value|
          request[key] = value
        end

        request.body = JSON.generate(body)

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          raise Net::HTTPError.new("HTTP #{response.code}: #{response.message}", response)
        end

        JSON.parse(response.body)
      end

      # Extract content from chat endpoint response
      # @param response [Hash] The parsed API response
      # @return [String] The generated content
      def extract_chat_content(response)
        message = response['message']
        raise ArgumentError, 'No message in response' if message.nil?

        content = message['content']
        raise ArgumentError, 'No content in message' if content.nil?

        content.strip
      end

      # Extract content from generate endpoint response
      # @param response [Hash] The parsed API response
      # @return [String] The generated content
      def extract_generate_content(response)
        content = response['response']
        raise ArgumentError, 'No response content' if content.nil?

        content.strip
      end

      # Check if the chat endpoint is supported
      # @return [Boolean] True if chat endpoint is available
      def supports_chat_endpoint?
        # Try a simple request to the chat endpoint
        uri = URI("#{@config.endpoint}#{CHAT_ENDPOINT}")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.read_timeout = 5
        http.open_timeout = 5

        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request.body = JSON.generate({
                                       model: @config.model,
                                       messages: [{ role: 'user', content: 'test' }],
                                       options: { num_predict: 1 },
                                       stream: false
                                     })

        response = http.request(request)
        response.is_a?(Net::HTTPSuccess)
      rescue StandardError
        false
      end

      # Check if the endpoint is accessible
      # @return [Boolean] True if the endpoint responds
      def endpoint_accessible?
        uri = URI(@config.endpoint)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'
        http.read_timeout = 5
        http.open_timeout = 5

        # Try to connect to the base endpoint
        request = Net::HTTP::Get.new('/')
        response = http.request(request)

        # Accept any response that indicates the server is running
        response.is_a?(Net::HTTPResponse)
      rescue StandardError
        false
      end
    end
  end
end
