# frozen_string_literal: true

require_relative '../../base_llm_optimizer'

module SpecScout
  module Optimizers
    module LlmBased
      # AI-powered optimizer that evaluates FactoryBot strategy using LLM analysis
      # Provides intelligent factory optimization recommendations with association awareness
      class FactoryOptimiser < BaseLlmOptimizer
        # System prompt for factory optimization analysis
        SYSTEM_PROMPT = <<~PROMPT
          You are an expert Ruby on Rails test optimization specialist with deep knowledge of:
          - FactoryBot strategies (create, build, build_stubbed) and their performance implications
          - ActiveRecord associations and their persistence requirements
          - Test isolation patterns and factory optimization techniques
          - Rails testing best practices and performance optimization

          Your role is to analyze factory usage patterns and provide specific, actionable recommendations for optimizing FactoryBot strategies. Always consider:
          1. Association requirements and access patterns
          2. Database persistence needs vs. performance gains
          3. Test isolation and reliability implications
          4. Specific code changes with performance estimates

          Provide concrete factory optimization examples and estimated performance improvements.
        PROMPT

        # Prompt template for factory optimization analysis
        PROMPT_TEMPLATE = <<~TEMPLATE
          You are a Ruby test optimization expert specializing in FactoryBot strategy optimization.

          PROFILE DATA:
          - Spec Location: {{spec_location}}
          - Factory Usage: {{factories}}
          - Database Operations: {{database_usage}}
          - Runtime: {{runtime_ms}}ms

          SPEC CONTENT:
          {{spec_content}}

          FACTORY DEFINITIONS:
          {{factory_definitions}}

          ASSOCIATION GRAPH:
          {{association_graph}}

          TASK:
          Analyze factory usage patterns and recommend optimal strategies.

          Consider:
          1. Current factory strategies (create vs build_stubbed vs build)
          2. Association requirements and access patterns
          3. Database persistence needs based on test behavior
          4. Performance impact of different strategies
          5. Specific code changes to optimize factory usage

          RESPONSE FORMAT:
          {
            "verdict": "prefer_build_stubbed|create_required|strategy_optimal",
            "confidence": "high|medium|low",
            "reasoning": "Detailed analysis of factory usage patterns and why specific strategies are recommended",
            "recommendations": [
              {
                "action": "optimize_factory_strategy",
                "current_usage": "create(:user, posts: create_list(:post, 3))",
                "optimized_usage": "build_stubbed(:user, posts: build_stubbed_list(:post, 3))",
                "performance_gain": "45% faster execution",
                "reasoning": "Associations don't require persistence for this test"
              }
            ],
            "metadata": {
              "analysis_type": "factory_optimization",
              "associations_analyzed": ["user", "posts"],
              "persistence_required": false,
              "performance_estimate": "Expected 30-50% improvement"
            }
          }

          Ensure your response is valid JSON and includes specific, actionable factory optimization recommendations.
        TEMPLATE

        protected

        # Get the prompt template for factory analysis
        # @return [String] Prompt template with placeholder variables
        def get_prompt_template
          PROMPT_TEMPLATE
        end

        # Get the system prompt for factory analysis
        # @return [String] System prompt for LLM context
        def get_system_prompt
          SYSTEM_PROMPT
        end

        # Build enhanced context for factory analysis
        # @param profile_data [ProfileData] Test profiling data
        # @param spec_content [String, nil] Optional spec file content
        # @return [Hash] Enhanced context hash for factory analysis
        def build_context(profile_data, spec_content)
          base_context = super(profile_data, spec_content)

          # Add factory-specific context enhancements
          base_context.merge(
            factory_definitions: format_factory_definitions(base_context[:factory_definitions]),
            association_graph: format_association_graph(base_context[:association_graph])
          )
        end

        private

        # Format factory definitions for display in prompt
        # @param definitions [Hash] Factory definitions hash
        # @return [String] Formatted factory definitions
        def format_factory_definitions(definitions)
          return 'No factory definitions available' if definitions.nil? || definitions.empty?

          formatted = definitions.map do |factory_name, definition|
            "#{factory_name}:\n#{definition}"
          end

          formatted.join("\n\n")
        end

        # Format association graph for display in prompt
        # @param graph [Hash] Association graph hash
        # @return [String] Formatted association information
        def format_association_graph(graph)
          return 'No association information available' if graph.nil? || graph.empty?

          formatted = graph.map do |factory_name, data|
            associations = data[:associations] || []
            strategy = data[:strategy] || 'unknown'
            count = data[:count] || 0

            association_info = associations.any? ? " (associations: #{associations.join(', ')})" : ' (no associations)'
            "#{factory_name}: #{strategy} strategy, #{count}x#{association_info}"
          end

          formatted.join("\n")
        end
      end
    end
  end
end
