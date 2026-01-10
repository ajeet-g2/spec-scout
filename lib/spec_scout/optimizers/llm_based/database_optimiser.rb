# frozen_string_literal: true

require_relative '../../base_llm_optimizer'

module SpecScout
  module Optimizers
    module LlmBased
      # AI-powered optimizer that analyzes database usage patterns using LLM intelligence
      # Provides intelligent database optimization recommendations with specific code changes
      class DatabaseOptimiser < BaseLlmOptimizer
        # System prompt for database optimization analysis
        SYSTEM_PROMPT = <<~PROMPT
          You are an expert Ruby on Rails test optimization specialist with deep knowledge of:
          - RSpec testing patterns and best practices
          - FactoryBot strategies and performance implications
          - ActiveRecord database optimization techniques
          - Test isolation and performance trade-offs

          Your role is to analyze test profiling data and provide specific, actionable recommendations for optimizing database usage in tests. Always consider:
          1. Test intent and appropriate isolation level
          2. Performance impact vs. test reliability
          3. Potential side effects of optimizations
          4. Rails-specific patterns and conventions

          Provide concrete code examples and estimated performance improvements.
        PROMPT

        # Prompt template for database optimization analysis
        PROMPT_TEMPLATE = <<~TEMPLATE
          You are a Ruby test optimization expert analyzing database usage patterns in RSpec tests.

          PROFILE DATA:
          - Spec Location: {{spec_location}}
          - Spec Type: {{spec_type}}
          - Runtime: {{runtime_ms}}ms
          - Database Queries: {{database_usage}}
          - Factory Usage: {{factories}}

          SPEC CONTENT:
          {{spec_content}}

          RELATED MODELS (if available):
          {{related_models}}

          OPTIMIZATION OPPORTUNITIES:
          {{optimization_opportunities}}

          TASK:
          Analyze the database usage patterns and provide optimization recommendations.

          Consider:
          1. Are database writes (INSERTs) necessary for this test?
          2. Could build_stubbed be used instead of create?
          3. Are the database reads (SELECTs) essential for test functionality?
          4. What is the test intent (unit vs integration)?
          5. What specific code changes would optimize performance?

          RESPONSE FORMAT:
          {
            "verdict": "db_unnecessary|db_required|db_unclear",
            "confidence": "high|medium|low",
            "reasoning": "Detailed explanation of your analysis including why database operations are or aren't needed",
            "recommendations": [
              {
                "action": "replace_factory_strategy",
                "from": "create(:user)",
                "to": "build_stubbed(:user)",
                "impact": "60% performance improvement",
                "reasoning": "User object doesn't need persistence for this test"
              }
            ],
            "metadata": {
              "analysis_type": "database_optimization",
              "risk_level": "low|medium|high",
              "performance_estimate": "Expected 40-60% improvement",
              "test_classification": "unit|integration|unclear"
            }
          }

          Ensure your response is valid JSON and includes specific, actionable recommendations.
        TEMPLATE

        protected

        # Get the prompt template for database analysis
        # @return [String] Prompt template with placeholder variables
        def get_prompt_template
          PROMPT_TEMPLATE
        end

        # Get the system prompt for database analysis
        # @return [String] System prompt for LLM context
        def get_system_prompt
          SYSTEM_PROMPT
        end

        # Build enhanced context for database analysis
        # @param profile_data [ProfileData] Test profiling data
        # @param spec_content [String, nil] Optional spec file content
        # @return [Hash] Enhanced context hash for database analysis
        def build_context(profile_data, spec_content)
          base_context = super(profile_data, spec_content)

          # Add database-specific context enhancements
          base_context.merge(
            related_models: format_related_models(base_context[:related_models]),
            optimization_opportunities: format_optimization_opportunities(base_context[:optimization_opportunities])
          )
        end

        private

        # Format related models for display in prompt
        # @param models [Array<String>] List of related model names
        # @return [String] Formatted model list
        def format_related_models(models)
          return 'No related models detected' if models.nil? || models.empty?

          "Related models: #{models.join(', ')}"
        end

        # Format optimization opportunities for display in prompt
        # @param opportunities [Array<String>] List of optimization patterns
        # @return [String] Formatted opportunities list
        def format_optimization_opportunities(opportunities)
          return 'No specific optimization patterns detected' if opportunities.nil? || opportunities.empty?

          "Detected patterns: #{opportunities.join(', ')}"
        end
      end
    end
  end
end
