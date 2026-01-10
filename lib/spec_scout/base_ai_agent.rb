# frozen_string_literal: true

require_relative 'optimizer_result'

module SpecScout
  # Abstract base class for AI-powered analysis agents
  # Provides common functionality for LLM-based agents that analyze profile data
  class BaseAIAgent
    attr_reader :agent_type, :llm_provider, :context_builder, :response_parser

    def initialize(agent_type: nil, llm_provider: nil, context_builder: nil, response_parser: nil)
      @agent_type = agent_type
      @llm_provider = llm_provider
      @context_builder = context_builder
      @response_parser = response_parser

      validate_dependencies!
    end

    # Abstract method to be implemented by subclasses
    # Analyzes profile data using AI and returns an OptimizerResult
    # @param profile_data [ProfileData] Normalized test profiling data
    # @param spec_content [String, nil] Optional spec file content for context
    # @return [OptimizerResult] Analysis result with verdict, confidence, and reasoning
    def analyze(profile_data, spec_content = nil)
      validate_profile_data!(profile_data)

      begin
        # Build context for the AI agent
        context = build_context(profile_data, spec_content)

        # Get prompt template and system prompt for this agent type
        prompt_template = get_prompt_template
        system_prompt = get_system_prompt

        # Generate AI response
        response = @llm_provider.generate(prompt_template, context, system_prompt)

        # Parse response into AgentResult
        parse_response(response)
      rescue StandardError => e
        create_error_result("AI analysis failed: #{e.message}")
      end
    end

    # Agent name for identification (derived from agent_type)
    def agent_name
      @agent_type
    end

    protected

    # Build context for AI analysis
    # Subclasses can override to add agent-specific context
    # @param profile_data [ProfileData] Test profiling data
    # @param spec_content [String, nil] Optional spec file content
    # @return [Hash] Context hash for prompt template rendering
    def build_context(profile_data, spec_content)
      @context_builder.build_context(profile_data, spec_content, @agent_type)
    end

    # Parse LLM response into OptimizerResult
    # Uses the response parser to handle JSON parsing and validation
    # @param response [String] Raw LLM response
    # @return [OptimizerResult] Parsed and validated result
    def parse_response(response)
      @response_parser.parse(response, @agent_type)
    end

    # Get prompt template for this agent type
    # Subclasses must implement this method
    # @return [String] Prompt template with placeholder variables
    def get_prompt_template
      raise NotImplementedError, 'Subclasses must implement #get_prompt_template'
    end

    # Get system prompt for this agent type
    # Subclasses can override to provide agent-specific system prompts
    # @return [String, nil] System prompt or nil for no system prompt
    def get_system_prompt
      nil
    end

    # Create error result for failed analysis
    # @param error_message [String] Error description
    # @return [OptimizerResult] Error result with optimizer_failed verdict
    def create_error_result(error_message)
      OptimizerResult.new(
        optimizer_name: @agent_type,
        verdict: :optimizer_failed,
        confidence: :low,
        reasoning: error_message,
        metadata: {
          error: true,
          timestamp: Time.now,
          ai_agent: true
        }
      )
    end

    private

    # Validate required dependencies are present
    def validate_dependencies!
      raise ArgumentError, 'agent_type is required' unless @agent_type
      raise ArgumentError, 'llm_provider is required' unless @llm_provider
      raise ArgumentError, 'context_builder is required' unless @context_builder
      raise ArgumentError, 'response_parser is required' unless @response_parser

      # Validate agent_type is a symbol
      raise ArgumentError, 'agent_type must be a Symbol' unless @agent_type.is_a?(Symbol)

      # Validate LLM provider has required methods
      raise ArgumentError, 'llm_provider must respond to #generate' unless @llm_provider.respond_to?(:generate)

      # Validate context builder has required methods
      unless @context_builder.respond_to?(:build_context)
        raise ArgumentError, 'context_builder must respond to #build_context'
      end

      # Validate response parser has required methods
      return if @response_parser.respond_to?(:parse)

      raise ArgumentError, 'response_parser must respond to #parse'
    end

    # Validate profile data structure
    # @param profile_data [ProfileData] Data to validate
    def validate_profile_data!(profile_data)
      raise ArgumentError, "Expected ProfileData, got #{profile_data.class}" unless profile_data.is_a?(ProfileData)

      return if profile_data.valid?

      raise ArgumentError, 'Invalid ProfileData structure'
    end
  end
end
