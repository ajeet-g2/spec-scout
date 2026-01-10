# frozen_string_literal: true

module SpecScout
  module LLMProviders
    # Abstract base class for LLM providers
    # Defines the interface that all LLM providers must implement
    class BaseLLMProvider
      # Generate a response from the LLM using the provided prompt and context
      # @param prompt_template [String] The prompt template with placeholders
      # @param context [Hash] Context data to substitute into the template
      # @param system_prompt [String, nil] Optional system prompt for the LLM
      # @return [String] The generated response from the LLM
      # @raise [NotImplementedError] Must be implemented by subclasses
      def generate(prompt_template, context, system_prompt = nil)
        raise NotImplementedError, "#{self.class} must implement #generate"
      end

      # Validate that a response from the LLM is properly formatted
      # @param response [String] The response to validate
      # @return [Boolean] True if the response is valid
      # @raise [NotImplementedError] Must be implemented by subclasses
      def validate_response(response)
        raise NotImplementedError, "#{self.class} must implement #validate_response"
      end

      # Check if the provider is properly configured and available
      # @return [Boolean] True if the provider is ready to use
      def available?
        raise NotImplementedError, "#{self.class} must implement #available?"
      end

      # Get the name of this provider
      # @return [Symbol] The provider name
      def provider_name
        raise NotImplementedError, "#{self.class} must implement #provider_name"
      end

      protected

      # Render a prompt template by substituting context variables
      # @param template [String] The template with {{variable}} placeholders
      # @param context [Hash] The context data to substitute
      # @return [String] The rendered prompt
      def render_template(template, context)
        rendered = template.dup
        context.each do |key, value|
          placeholder = "{{#{key}}}"
          rendered = rendered.gsub(placeholder, value.to_s)
        end
        rendered
      end

      # Validate that required configuration is present
      # @param config [Object] The configuration object to validate
      # @param required_fields [Array<Symbol>] Required configuration fields
      # @raise [ArgumentError] If required fields are missing
      def validate_config(config, required_fields)
        missing_fields = required_fields.select { |field| config.send(field).nil? || config.send(field).empty? }
        return if missing_fields.empty?

        provider_name_safe = begin
          provider_name
        rescue NotImplementedError
          'LLM provider'
        end

        raise ArgumentError, "Missing required configuration for #{provider_name_safe}: #{missing_fields.join(', ')}"
      end

      # Handle API errors consistently across providers
      # @param error [StandardError] The error that occurred
      # @return [String] A fallback error response
      def handle_api_error(error)
        error_message = case error
                        when Timeout::Error
                          'API request timed out'
                        when Net::HTTPError
                          "HTTP error: #{error.message}"
                        when JSON::ParserError
                          'Invalid JSON response from API'
                        else
                          "API error: #{error.message}"
                        end

        "Error communicating with #{provider_name}: #{error_message}"
      rescue NotImplementedError
        # If provider_name is not implemented, use generic message
        "Error communicating with LLM provider: #{error_message}"
      end
    end
  end
end
