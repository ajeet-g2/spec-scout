# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SpecScout::LlmOptimizerManager do
  let(:config) { SpecScout::Configuration.new }
  let(:profile_data) do
    SpecScout::ProfileData.new(
      example_location: 'spec/models/user_spec.rb:42',
      spec_type: :model,
      runtime_ms: 38,
      factories: { user: { strategy: :create, count: 1 } },
      db: { total_queries: 6, inserts: 1, selects: 5 },
      events: {},
      metadata: {}
    )
  end

  subject(:llm_optimizer_manager) { described_class.new(config) }

  describe '#initialize' do
    it 'initializes with configuration' do
      expect(llm_optimizer_manager.config).to eq(config)
      expect(llm_optimizer_manager.optimizer_registry).to be_a(SpecScout::OptimizerRegistry)
      expect(llm_optimizer_manager.context_builder).to be_a(SpecScout::ContextBuilder)
      expect(llm_optimizer_manager.response_parser).to be_a(SpecScout::ResponseParser)
    end

    context 'when LLM provider is available' do
      before do
        config.openai_config.api_key = 'test-key'
        allow(SpecScout::LLMProviders).to receive(:create_provider).and_return(double('provider'))
      end

      it 'creates an LLM provider' do
        manager = described_class.new(config)
        expect(manager.llm_provider).not_to be_nil
      end
    end

    context 'when LLM provider is not available' do
      before do
        config.openai_config.api_key = nil
      end

      it 'does not create an LLM provider' do
        manager = described_class.new(config)
        expect(manager.llm_provider).to be_nil
      end
    end
  end

  describe '#llm_optimizers_available?' do
    context 'when LLM provider is available and LLM optimizers are registered' do
      before do
        config.openai_config.api_key = 'test-key'
        allow(SpecScout::LLMProviders).to receive(:create_provider).and_return(double('provider'))
        allow(llm_optimizer_manager.optimizer_registry).to receive(:llm_optimizer_registered?).and_return(true)
      end

      it 'returns true' do
        expect(llm_optimizer_manager.llm_optimizers_available?).to be true
      end
    end

    context 'when LLM provider is not available' do
      before do
        config.openai_config.api_key = nil
      end

      it 'returns false' do
        expect(llm_optimizer_manager.llm_optimizers_available?).to be false
      end
    end

    context 'when no LLM optimizers are enabled' do
      before do
        config.openai_config.api_key = 'test-key'
        allow(SpecScout::LLMProviders).to receive(:create_provider).and_return(double('provider'))
        allow(llm_optimizer_manager.optimizer_registry).to receive(:llm_optimizer_registered?).and_return(false)
      end

      it 'returns false' do
        expect(llm_optimizer_manager.llm_optimizers_available?).to be false
      end
    end
  end

  describe '#enabled_llm_optimizers' do
    before do
      config.enabled_optimizers = %i[database factory intent risk]
    end

    it 'returns only LLM-supported optimizer types' do
      allow(llm_optimizer_manager.optimizer_registry).to receive(:llm_optimizer_registered?).with(:database).and_return(true)
      allow(llm_optimizer_manager.optimizer_registry).to receive(:llm_optimizer_registered?).with(:factory).and_return(false)
      allow(llm_optimizer_manager.optimizer_registry).to receive(:llm_optimizer_registered?).with(:intent).and_return(true)
      allow(llm_optimizer_manager.optimizer_registry).to receive(:llm_optimizer_registered?).with(:risk).and_return(false)

      expect(llm_optimizer_manager.enabled_llm_optimizers).to eq(%i[database intent])
    end
  end

  describe '#run_optimizers' do
    context 'when LLM optimizers are not available' do
      before do
        config.openai_config.api_key = nil
        allow(llm_optimizer_manager).to receive(:llm_optimizers_available?).and_return(false)
      end

      it 'falls back to rule-based optimizers' do
        results = llm_optimizer_manager.run_optimizers(profile_data)
        expect(results).not_to be_empty
        expect(results.all? { |result| result.metadata[:fallback] }).to be true
      end
    end

    context 'when LLM optimizers are available but none are enabled' do
      before do
        config.openai_config.api_key = 'test-key'
        allow(SpecScout::LLMProviders).to receive(:create_provider).and_return(double('provider'))
        allow(llm_optimizer_manager).to receive(:enabled_llm_optimizers).and_return([])
      end

      it 'returns empty array' do
        results = llm_optimizer_manager.run_optimizers(profile_data)
        expect(results).to eq([])
      end
    end

    context 'when LLM optimizer fails and fallback succeeds' do
      let(:mock_database_optimizer) { double('database_optimizer') }
      let(:fallback_result) do
        SpecScout::OptimizerResult.new(
          optimizer_name: :database,
          verdict: :db_unnecessary,
          confidence: :high,
          reasoning: 'Fallback analysis',
          metadata: { fallback: true, llm_optimizer_failed: true }
        )
      end

      before do
        config.openai_config.api_key = 'test-key'
        config.enabled_optimizers = [:database]

        allow(SpecScout::LLMProviders).to receive(:create_provider).and_return(double('provider'))
        allow(llm_optimizer_manager.optimizer_registry).to receive(:llm_optimizer_registered?).with(:database).and_return(true)
        allow(llm_optimizer_manager.optimizer_registry).to receive(:get_llm_optimizer).with(:database).and_return(nil)

        # Mock fallback optimizer creation
        allow(SpecScout::Optimizers::RuleBased::DatabaseOptimiser).to receive(:new).with(profile_data).and_return(mock_database_optimizer)
        allow(mock_database_optimizer).to receive(:evaluate).and_return(fallback_result)
      end

      it 'falls back to rule-based optimizer' do
        results = llm_optimizer_manager.run_optimizers(profile_data)

        expect(results.size).to eq(1)
        expect(results.first.optimizer_name).to eq(:database)
        expect(results.first.metadata[:fallback]).to be true
        expect(results.first.metadata[:llm_optimizer_failed]).to be true
      end
    end
  end

  describe '#register_llm_optimizer' do
    let(:mock_optimizer_class) { double('MockLLMOptimizer') }

    it 'delegates to optimizer registry' do
      expect(llm_optimizer_manager.optimizer_registry).to receive(:register_llm_optimizer).with(:custom,
                                                                                                mock_optimizer_class)

      llm_optimizer_manager.register_llm_optimizer(:custom, mock_optimizer_class)
    end
  end

  describe '#llm_optimizer_supported?' do
    it 'delegates to optimizer registry' do
      expect(llm_optimizer_manager.optimizer_registry).to receive(:llm_optimizer_registered?).with(:database).and_return(true)

      expect(llm_optimizer_manager.llm_optimizer_supported?(:database)).to be true
    end
  end
end
