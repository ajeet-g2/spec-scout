# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SpecScout::BaseLlmOptimizer do
  let(:optimizer_type) { :test_optimizer }
  let(:mock_llm_provider) { double('llm_provider') }
  let(:mock_context_builder) { double('context_builder') }
  let(:mock_response_parser) { double('response_parser') }

  let(:valid_profile_data) do
    SpecScout::ProfileData.new(
      example_location: 'spec/models/user_spec.rb:42',
      spec_type: :model,
      runtime_ms: 150,
      factories: { user: { strategy: :create, count: 1 } },
      db: { total_queries: 5, inserts: 1, selects: 4 },
      events: {},
      metadata: {}
    )
  end

  # Create a concrete test implementation
  let(:test_optimizer_class) do
    Class.new(described_class) do
      def get_prompt_template
        'Test prompt template with {{spec_location}}'
      end

      def get_system_prompt
        'Test system prompt'
      end
    end
  end

  describe '#initialize' do
    it 'initializes with required dependencies' do
      allow(mock_llm_provider).to receive(:respond_to?).with(:generate).and_return(true)
      allow(mock_context_builder).to receive(:respond_to?).with(:build_context).and_return(true)
      allow(mock_response_parser).to receive(:respond_to?).with(:parse).and_return(true)

      optimizer = test_optimizer_class.new(
        optimizer_type: optimizer_type,
        llm_provider: mock_llm_provider,
        context_builder: mock_context_builder,
        response_parser: mock_response_parser
      )

      expect(optimizer.optimizer_type).to eq(optimizer_type)
      expect(optimizer.llm_provider).to eq(mock_llm_provider)
      expect(optimizer.context_builder).to eq(mock_context_builder)
      expect(optimizer.response_parser).to eq(mock_response_parser)
    end

    it 'raises error when optimizer_type is missing' do
      expect do
        test_optimizer_class.new(
          llm_provider: mock_llm_provider,
          context_builder: mock_context_builder,
          response_parser: mock_response_parser
        )
      end.to raise_error(ArgumentError, 'optimizer_type is required')
    end

    it 'raises error when optimizer_type is not a Symbol' do
      expect do
        test_optimizer_class.new(
          optimizer_type: 'string_type',
          llm_provider: mock_llm_provider,
          context_builder: mock_context_builder,
          response_parser: mock_response_parser
        )
      end.to raise_error(ArgumentError, 'optimizer_type must be a Symbol')
    end

    it 'raises error when llm_provider is missing' do
      expect do
        test_optimizer_class.new(
          optimizer_type: optimizer_type,
          context_builder: mock_context_builder,
          response_parser: mock_response_parser
        )
      end.to raise_error(ArgumentError, 'llm_provider is required')
    end

    it 'raises error when llm_provider does not respond to generate' do
      invalid_provider = double('invalid_provider')
      allow(invalid_provider).to receive(:respond_to?).with(:generate).and_return(false)

      expect do
        test_optimizer_class.new(
          optimizer_type: optimizer_type,
          llm_provider: invalid_provider,
          context_builder: mock_context_builder,
          response_parser: mock_response_parser
        )
      end.to raise_error(ArgumentError, 'llm_provider must respond to #generate')
    end

    it 'raises error when context_builder is missing' do
      allow(mock_llm_provider).to receive(:respond_to?).with(:generate).and_return(true)

      expect do
        test_optimizer_class.new(
          optimizer_type: optimizer_type,
          llm_provider: mock_llm_provider,
          response_parser: mock_response_parser
        )
      end.to raise_error(ArgumentError, 'context_builder is required')
    end

    it 'raises error when response_parser is missing' do
      allow(mock_llm_provider).to receive(:respond_to?).with(:generate).and_return(true)
      allow(mock_context_builder).to receive(:respond_to?).with(:build_context).and_return(true)

      expect do
        test_optimizer_class.new(
          optimizer_type: optimizer_type,
          llm_provider: mock_llm_provider,
          context_builder: mock_context_builder
        )
      end.to raise_error(ArgumentError, 'response_parser is required')
    end
  end

  describe '#analyze' do
    let(:optimizer) do
      allow(mock_llm_provider).to receive(:respond_to?).with(:generate).and_return(true)
      allow(mock_context_builder).to receive(:respond_to?).with(:build_context).and_return(true)
      allow(mock_response_parser).to receive(:respond_to?).with(:parse).and_return(true)

      test_optimizer_class.new(
        optimizer_type: optimizer_type,
        llm_provider: mock_llm_provider,
        context_builder: mock_context_builder,
        response_parser: mock_response_parser
      )
    end

    let(:mock_context) { { spec_location: 'spec/models/user_spec.rb:42' } }
    let(:mock_response) { '{"verdict": "test_verdict", "confidence": "high", "reasoning": "Test reasoning"}' }
    let(:mock_optimizer_result) do
      SpecScout::OptimizerResult.new(
        optimizer_name: optimizer_type,
        verdict: :test_verdict,
        confidence: :high,
        reasoning: 'Test reasoning',
        metadata: {}
      )
    end

    it 'successfully analyzes profile data' do
      allow(mock_context_builder).to receive(:build_context)
        .with(valid_profile_data, nil, optimizer_type)
        .and_return(mock_context)

      allow(mock_llm_provider).to receive(:generate)
        .with('Test prompt template with {{spec_location}}', mock_context, 'Test system prompt')
        .and_return(mock_response)

      allow(mock_response_parser).to receive(:parse)
        .with(mock_response, optimizer_type)
        .and_return(mock_optimizer_result)

      result = optimizer.analyze(valid_profile_data)

      expect(result).to eq(mock_optimizer_result)
    end

    it 'analyzes with spec content' do
      spec_content = 'RSpec.describe User do...'

      allow(mock_context_builder).to receive(:build_context)
        .with(valid_profile_data, spec_content, optimizer_type)
        .and_return(mock_context)

      allow(mock_llm_provider).to receive(:generate)
        .with('Test prompt template with {{spec_location}}', mock_context, 'Test system prompt')
        .and_return(mock_response)

      allow(mock_response_parser).to receive(:parse)
        .with(mock_response, optimizer_type)
        .and_return(mock_optimizer_result)

      result = optimizer.analyze(valid_profile_data, spec_content)

      expect(result).to eq(mock_optimizer_result)
    end

    it 'raises error for invalid profile data' do
      expect do
        optimizer.analyze('invalid_profile_data')
      end.to raise_error(ArgumentError, /Expected ProfileData/)
    end

    it 'raises error for invalid ProfileData structure' do
      invalid_profile = SpecScout::ProfileData.new
      invalid_profile.example_location = nil

      expect do
        optimizer.analyze(invalid_profile)
      end.to raise_error(ArgumentError, 'Invalid ProfileData structure')
    end

    it 'returns error result when LLM provider fails' do
      allow(mock_context_builder).to receive(:build_context)
        .with(valid_profile_data, nil, optimizer_type)
        .and_return(mock_context)

      allow(mock_llm_provider).to receive(:generate)
        .and_raise(StandardError, 'LLM API error')

      result = optimizer.analyze(valid_profile_data)

      expect(result).to be_a(SpecScout::OptimizerResult)
      expect(result.optimizer_name).to eq(optimizer_type)
      expect(result.verdict).to eq(:optimizer_failed)
      expect(result.confidence).to eq(:low)
      expect(result.reasoning).to include('LLM analysis failed: LLM API error')
      expect(result.metadata[:error]).to be true
      expect(result.metadata[:llm_optimizer]).to be true
    end

    it 'returns error result when context building fails' do
      allow(mock_context_builder).to receive(:build_context)
        .and_raise(StandardError, 'Context building error')

      result = optimizer.analyze(valid_profile_data)

      expect(result).to be_a(SpecScout::OptimizerResult)
      expect(result.verdict).to eq(:optimizer_failed)
      expect(result.reasoning).to include('LLM analysis failed: Context building error')
    end

    it 'returns error result when response parsing fails' do
      allow(mock_context_builder).to receive(:build_context)
        .with(valid_profile_data, nil, optimizer_type)
        .and_return(mock_context)

      allow(mock_llm_provider).to receive(:generate)
        .with('Test prompt template with {{spec_location}}', mock_context, 'Test system prompt')
        .and_return(mock_response)

      allow(mock_response_parser).to receive(:parse)
        .and_raise(StandardError, 'Response parsing error')

      result = optimizer.analyze(valid_profile_data)

      expect(result).to be_a(SpecScout::OptimizerResult)
      expect(result.verdict).to eq(:optimizer_failed)
      expect(result.reasoning).to include('LLM analysis failed: Response parsing error')
    end
  end

  describe '#optimizer_name' do
    let(:optimizer) do
      allow(mock_llm_provider).to receive(:respond_to?).with(:generate).and_return(true)
      allow(mock_context_builder).to receive(:respond_to?).with(:build_context).and_return(true)
      allow(mock_response_parser).to receive(:respond_to?).with(:parse).and_return(true)

      test_optimizer_class.new(
        optimizer_type: optimizer_type,
        llm_provider: mock_llm_provider,
        context_builder: mock_context_builder,
        response_parser: mock_response_parser
      )
    end

    it 'returns the optimizer_type as optimizer_name' do
      expect(optimizer.optimizer_name).to eq(optimizer_type)
    end
  end

  describe 'abstract methods' do
    let(:abstract_optimizer_class) { described_class }

    it 'raises NotImplementedError for get_prompt_template' do
      allow(mock_llm_provider).to receive(:respond_to?).with(:generate).and_return(true)
      allow(mock_context_builder).to receive(:respond_to?).with(:build_context).and_return(true)
      allow(mock_response_parser).to receive(:respond_to?).with(:parse).and_return(true)

      optimizer = abstract_optimizer_class.new(
        optimizer_type: optimizer_type,
        llm_provider: mock_llm_provider,
        context_builder: mock_context_builder,
        response_parser: mock_response_parser
      )

      expect do
        optimizer.send(:get_prompt_template)
      end.to raise_error(NotImplementedError, 'Subclasses must implement #get_prompt_template')
    end
  end

  describe '#get_system_prompt' do
    let(:optimizer) do
      allow(mock_llm_provider).to receive(:respond_to?).with(:generate).and_return(true)
      allow(mock_context_builder).to receive(:respond_to?).with(:build_context).and_return(true)
      allow(mock_response_parser).to receive(:respond_to?).with(:parse).and_return(true)

      test_optimizer_class.new(
        optimizer_type: optimizer_type,
        llm_provider: mock_llm_provider,
        context_builder: mock_context_builder,
        response_parser: mock_response_parser
      )
    end

    it 'returns system prompt from subclass' do
      expect(optimizer.send(:get_system_prompt)).to eq('Test system prompt')
    end
  end

  describe 'optimizer without system prompt' do
    let(:no_system_prompt_optimizer_class) do
      Class.new(described_class) do
        def get_prompt_template
          'Test prompt template'
        end
        # get_system_prompt not overridden, should return nil
      end
    end

    let(:optimizer) do
      allow(mock_llm_provider).to receive(:respond_to?).with(:generate).and_return(true)
      allow(mock_context_builder).to receive(:respond_to?).with(:build_context).and_return(true)
      allow(mock_response_parser).to receive(:respond_to?).with(:parse).and_return(true)

      no_system_prompt_optimizer_class.new(
        optimizer_type: optimizer_type,
        llm_provider: mock_llm_provider,
        context_builder: mock_context_builder,
        response_parser: mock_response_parser
      )
    end

    it 'returns nil for system prompt by default' do
      expect(optimizer.send(:get_system_prompt)).to be_nil
    end

    it 'calls LLM provider with nil system prompt' do
      mock_context = { spec_location: 'test' }
      mock_response = '{"verdict": "test", "confidence": "high", "reasoning": "test"}'
      mock_result = SpecScout::OptimizerResult.new(optimizer_name: optimizer_type, verdict: :test, confidence: :high,
                                                   reasoning: 'test')

      allow(mock_context_builder).to receive(:build_context).and_return(mock_context)
      allow(mock_llm_provider).to receive(:generate)
        .with('Test prompt template', mock_context, nil)
        .and_return(mock_response)
      allow(mock_response_parser).to receive(:parse).and_return(mock_result)

      optimizer.analyze(valid_profile_data)

      expect(mock_llm_provider).to have_received(:generate)
        .with('Test prompt template', mock_context, nil)
    end
  end
end
