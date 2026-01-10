# frozen_string_literal: true

require_relative '../../base_llm_optimizer'

module SpecScout
  module Optimizers
    module LlmBased
      # AI-powered optimizer that identifies optimization risks using LLM pattern recognition
      # Provides intelligent side-effect detection and safety recommendations
      class RiskOptimiser < BaseLlmOptimizer
        # System prompt for risk assessment analysis
        SYSTEM_PROMPT = <<~PROMPT
          You are an expert Ruby on Rails testing safety specialist with deep knowledge of:
          - ActiveRecord callbacks (after_commit, after_create, etc.) and their side effects
          - Complex association dependencies and cascade behaviors
          - Rails background job patterns (Sidekiq, DelayedJob, etc.)
          - Test optimization risks and safety considerations

          Your role is to identify potential risks in applying test optimizations by analyzing code patterns and dependencies. Always consider:
          1. ActiveRecord callbacks that might be triggered by factory creation
          2. Side effects like email sending, job queuing, or external API calls
          3. Complex association chains that might break with build_stubbed
          4. State-dependent behaviors that require database persistence

          Provide specific risk assessments with concrete mitigation strategies.
        PROMPT

        # Prompt template for risk assessment analysis
        PROMPT_TEMPLATE = <<~TEMPLATE
          You are a Ruby testing safety expert who identifies risks in test optimizations.

          PROFILE DATA:
          - Spec Location: {{spec_location}}
          - Factory Usage: {{factories}}
          - Database Usage: {{database_usage}}

          SPEC CONTENT:
          {{spec_content}}

          RAILS MODEL CONTENT (if available):
          {{model_content}}

          CALLBACK ANALYSIS:
          {{callback_analysis}}

          TASK:
          Identify potential risks in applying test optimizations.

          Consider:
          1. ActiveRecord callbacks (after_commit, after_create, etc.) that might be affected
          2. Complex association dependencies that require database persistence
          3. Side effects like email sending, job queuing, or external integrations
          4. State-dependent test behavior that might break with optimization
          5. Specific mitigation strategies for identified risks

          RESPONSE FORMAT:
          {
            "verdict": "safe_to_optimize|potential_side_effects|high_risk",
            "confidence": "high|medium|low",
            "reasoning": "Risk analysis and safety assessment with specific evidence from code analysis",
            "risk_factors": [
              {
                "type": "after_commit_callback",
                "severity": "high",
                "description": "User model has after_commit callback that sends emails",
                "location": "app/models/user.rb:15",
                "mitigation": "Test callback separately or stub email delivery"
              }
            ],
            "safety_recommendations": [
              "Apply optimizations in development environment first",
              "Monitor for behavioral changes after optimization",
              "Consider stubbing external dependencies"
            ],
            "metadata": {
              "analysis_type": "risk_assessment",
              "callbacks_detected": ["after_commit", "after_create"],
              "side_effects_likely": true,
              "optimization_safety": "proceed_with_caution"
            }
          }

          Ensure your response is valid JSON and includes specific risk factors with actionable mitigation strategies.
        TEMPLATE

        protected

        # Get the prompt template for risk analysis
        # @return [String] Prompt template with placeholder variables
        def get_prompt_template
          PROMPT_TEMPLATE
        end

        # Get the system prompt for risk analysis
        # @return [String] System prompt for LLM context
        def get_system_prompt
          SYSTEM_PROMPT
        end

        # Build enhanced context for risk analysis
        # @param profile_data [ProfileData] Test profiling data
        # @param spec_content [String, nil] Optional spec file content
        # @return [Hash] Enhanced context hash for risk analysis
        def build_context(profile_data, spec_content)
          base_context = super(profile_data, spec_content)

          # Add risk-specific context enhancements
          base_context.merge(
            model_content: format_model_content(base_context[:model_content]),
            callback_analysis: format_callback_analysis(base_context[:callback_analysis])
          )
        end

        private

        # Format model content for display in prompt
        # @param content [String, nil] Model file content
        # @return [String] Formatted model content or placeholder
        def format_model_content(content)
          return 'No model content available for analysis' if content.nil? || content.empty?

          # Truncate very long model files to focus on key parts
          if content.length > 2000
            "#{content[0..2000]}...\n[Content truncated for analysis]"
          else
            content
          end
        end

        # Format callback analysis for display in prompt
        # @param analysis [Hash] Callback analysis hash
        # @return [String] Formatted callback information
        def format_callback_analysis(analysis)
          return 'No callback analysis available' if analysis.nil? || analysis.empty?

          callback_info = analysis.map do |callback_type, methods|
            "#{callback_type}: #{methods.join(', ')}"
          end

          "Detected callbacks: #{callback_info.join('; ')}"
        end
      end
    end
  end
end
