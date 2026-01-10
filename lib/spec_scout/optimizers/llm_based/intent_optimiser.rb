# frozen_string_literal: true

require_relative '../../base_llm_optimizer'

module SpecScout
  module Optimizers
    module LlmBased
      # AI-powered optimizer that classifies test intent using LLM code understanding
      # Provides intelligent test boundary detection and structure recommendations
      class IntentOptimiser < BaseLlmOptimizer
        # System prompt for test intent classification
        SYSTEM_PROMPT = <<~PROMPT
          You are an expert Ruby testing specialist who analyzes test intent and classification with deep knowledge of:
          - RSpec testing patterns and conventions
          - Unit vs integration test boundaries and characteristics
          - Rails testing best practices and file organization
          - Test isolation patterns and performance implications

          Your role is to analyze test code and behavior to determine the appropriate test classification and optimization approach. Always consider:
          1. File location and naming conventions
          2. Test behavior patterns and dependencies
          3. External system boundaries and integration points
          4. Appropriate optimization strategies for different test types

          Provide specific insights about test intent and actionable recommendations for test structure improvements.
        PROMPT

        # Prompt template for test intent classification
        PROMPT_TEMPLATE = <<~TEMPLATE
          You are a Ruby testing expert who analyzes test intent and classification.

          PROFILE DATA:
          - Spec Location: {{spec_location}}
          - Spec Type: {{spec_type}}
          - Runtime: {{runtime_ms}}ms
          - Database Usage: {{database_usage}}
          - External Dependencies: {{events}}

          SPEC CONTENT:
          {{spec_content}}

          FILE STRUCTURE:
          {{file_structure}}

          TEST DEPENDENCIES:
          {{test_dependencies}}

          TASK:
          Analyze the test to determine its intent and appropriate classification.

          Consider:
          1. File location and naming conventions (spec/models vs spec/integration)
          2. Test behavior patterns (isolated unit testing vs cross-boundary integration)
          3. External dependencies and system boundaries crossed
          4. Database usage patterns and persistence requirements
          5. Appropriate optimization strategies for the identified test type

          RESPONSE FORMAT:
          {
            "verdict": "unit_test_behavior|integration_test_behavior|intent_unclear",
            "confidence": "high|medium|low",
            "reasoning": "Analysis of test intent and behavior patterns with specific evidence from the code",
            "test_classification": {
              "primary_type": "unit|integration|system",
              "boundaries_crossed": ["database", "external_api", "file_system"],
              "optimization_approach": "aggressive|conservative|none",
              "isolation_level": "high|medium|low"
            },
            "recommendations": [
              {
                "action": "improve_test_isolation",
                "description": "Move database-dependent tests to integration directory",
                "reasoning": "Current test crosses database boundary but is in unit test location"
              }
            ],
            "metadata": {
              "analysis_type": "intent_classification",
              "file_location_signal": "unit|integration|unclear",
              "behavior_signal": "unit|integration|mixed",
              "optimization_potential": "high|medium|low"
            }
          }

          Ensure your response is valid JSON and includes specific insights about test intent and structure.
        TEMPLATE

        protected

        # Get the prompt template for intent analysis
        # @return [String] Prompt template with placeholder variables
        def get_prompt_template
          PROMPT_TEMPLATE
        end

        # Get the system prompt for intent analysis
        # @return [String] System prompt for LLM context
        def get_system_prompt
          SYSTEM_PROMPT
        end

        # Build enhanced context for intent analysis
        # @param profile_data [ProfileData] Test profiling data
        # @param spec_content [String, nil] Optional spec file content
        # @return [Hash] Enhanced context hash for intent analysis
        def build_context(profile_data, spec_content)
          base_context = super(profile_data, spec_content)

          # Add intent-specific context enhancements
          base_context.merge(
            file_structure: format_file_structure(base_context[:file_structure]),
            test_dependencies: format_test_dependencies(base_context[:test_dependencies])
          )
        end

        private

        # Format file structure information for display in prompt
        # @param structure [Hash] File structure analysis hash
        # @return [String] Formatted file structure information
        def format_file_structure(structure)
          return 'No file structure information available' if structure.nil? || structure.empty?

          parts = []
          parts << "Directory depth: #{structure[:directory_depth]}" if structure[:directory_depth]
          parts << "Inferred spec type: #{structure[:spec_type_from_path]}" if structure[:spec_type_from_path]
          parts << "Nested structure: #{structure[:is_nested] ? 'yes' : 'no'}" if structure.key?(:is_nested)
          parts << "File name: #{structure[:file_name]}" if structure[:file_name]

          parts.join(', ')
        end

        # Format test dependencies information for display in prompt
        # @param dependencies [Hash] Test dependencies analysis hash
        # @return [String] Formatted dependencies information
        def format_test_dependencies(dependencies)
          return 'No test dependencies information available' if dependencies.nil? || dependencies.empty?

          dependency_flags = []
          dependency_flags << 'requires database' if dependencies[:requires_database]
          dependency_flags << 'uses external services' if dependencies[:uses_external_services]
          dependency_flags << 'has file operations' if dependencies[:has_file_operations]
          dependency_flags << 'uses time travel' if dependencies[:uses_time_travel]
          dependency_flags << 'requires javascript' if dependencies[:requires_javascript]

          return 'No external dependencies detected' if dependency_flags.empty?

          "Dependencies: #{dependency_flags.join(', ')}"
        end
      end
    end
  end
end
