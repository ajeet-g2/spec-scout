# frozen_string_literal: true

require 'json'
require_relative 'optimizer_result'

module SpecScout
  # Parses and validates LLM responses for AI agents
  class ResponseParser
    # Valid agent types that can be parsed
    VALID_AGENT_TYPES = %i[database factory intent risk].freeze

    # Valid verdict mappings for each agent type
    VALID_VERDICTS = {
      database: %i[db_unnecessary db_required db_unclear optimizer_failed],
      factory: %i[prefer_build_stubbed create_required strategy_optimal optimizer_failed],
      intent: %i[unit_test_behavior integration_test_behavior intent_unclear optimizer_failed],
      risk: %i[safe_to_optimize potential_side_effects high_risk optimizer_failed]
    }.freeze

    # Valid confidence levels
    VALID_CONFIDENCE_LEVELS = %i[high medium low none].freeze

    def initialize
      # Initialize any required state
    end

    # Parse LLM response into OptimizerResult
    # @param response [String] Raw LLM response (expected to be JSON)
    # @param agent_type [Symbol] Type of optimizer that generated the response
    # @return [OptimizerResult] Parsed and validated optimizer result
    def parse(response, agent_type)
      validate_agent_type!(agent_type)

      parsed = parse_json(response)
      validate_response_structure!(parsed, agent_type)

      create_agent_result(parsed, agent_type)
    rescue JSON::ParserError => e
      create_fallback_result(agent_type, "Invalid JSON response: #{e.message}")
    rescue ArgumentError => e
      create_fallback_result(agent_type, "Response validation failed: #{e.message}")
    rescue StandardError => e
      create_fallback_result(agent_type, "Response parsing failed: #{e.message}")
    end

    private

    # Parse JSON with error handling
    def parse_json(response)
      return {} if response.nil? || response.strip.empty?

      JSON.parse(response)
    rescue JSON::ParserError => e
      raise JSON::ParserError, "Failed to parse JSON: #{e.message}"
    end

    # Validate that the agent type is supported
    def validate_agent_type!(agent_type)
      return if VALID_AGENT_TYPES.include?(agent_type)

      raise ArgumentError, "Unsupported agent type: #{agent_type}. Valid types: #{VALID_AGENT_TYPES}"
    end

    # Validate the structure of the parsed response
    def validate_response_structure!(parsed, agent_type)
      raise ArgumentError, "Response must be a JSON object, got: #{parsed.class}" unless parsed.is_a?(Hash)

      validate_required_fields!(parsed)
      validate_verdict!(parsed['verdict'], agent_type)
      validate_confidence!(parsed['confidence'])
    end

    # Validate that all required fields are present
    def validate_required_fields!(parsed)
      required_fields = %w[verdict confidence reasoning]
      missing_fields = required_fields - parsed.keys

      return if missing_fields.empty?

      raise ArgumentError, "Missing required fields: #{missing_fields.join(', ')}"
    end

    # Validate the verdict field
    def validate_verdict!(verdict, agent_type)
      return if verdict.nil?

      verdict_sym = verdict.to_sym
      valid_verdicts = VALID_VERDICTS[agent_type] || []

      return if valid_verdicts.include?(verdict_sym)

      raise ArgumentError,
            "Invalid verdict '#{verdict}' for agent type '#{agent_type}'. Valid verdicts: #{valid_verdicts}"
    end

    # Validate the confidence field
    def validate_confidence!(confidence)
      return if confidence.nil?

      confidence_sym = confidence.to_sym

      return if VALID_CONFIDENCE_LEVELS.include?(confidence_sym)

      raise ArgumentError, "Invalid confidence level '#{confidence}'. Valid levels: #{VALID_CONFIDENCE_LEVELS}"
    end

    # Create OptimizerResult from parsed response
    def create_agent_result(parsed, agent_type)
      OptimizerResult.new(
        optimizer_name: agent_type,
        verdict: parsed['verdict']&.to_sym || :no_verdict,
        confidence: parsed['confidence']&.to_sym || :low,
        reasoning: parsed['reasoning'] || '',
        metadata: build_metadata(parsed, agent_type)
      )
    end

    # Build metadata hash from parsed response
    def build_metadata(parsed, _agent_type)
      metadata = parsed['metadata'] || {}

      # Add additional fields that might be present in AI responses
      metadata = metadata.merge(extract_additional_fields(parsed))

      # Ensure metadata is a hash
      metadata.is_a?(Hash) ? metadata : {}
    end

    # Extract additional fields from response that should be included in metadata
    def extract_additional_fields(parsed)
      additional_fields = {}

      # Include recommendations if present
      additional_fields[:recommendations] = parsed['recommendations'] if parsed['recommendations'].is_a?(Array)

      # Include performance impact if present
      additional_fields[:performance_impact] = parsed['performance_impact'] if parsed['performance_impact']

      # Include risk assessment if present
      additional_fields[:risk_assessment] = parsed['risk_assessment'] if parsed['risk_assessment']

      # Include test classification if present (for intent agent)
      additional_fields[:test_classification] = parsed['test_classification'] if parsed['test_classification']

      # Include risk factors if present (for risk agent)
      additional_fields[:risk_factors] = parsed['risk_factors'] if parsed['risk_factors'].is_a?(Array)

      # Include safety recommendations if present (for risk agent)
      if parsed['safety_recommendations'].is_a?(Array)
        additional_fields[:safety_recommendations] = parsed['safety_recommendations']
      end

      additional_fields
    end

    # Create fallback result for parsing failures
    def create_fallback_result(agent_type, error_message)
      OptimizerResult.new(
        optimizer_name: agent_type,
        verdict: :optimizer_failed,
        confidence: :low,
        reasoning: error_message,
        metadata: {
          error: true,
          timestamp: Time.now,
          parser_error: true
        }
      )
    end
  end
end
