# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SpecScout::Configuration do
  describe '#initialize' do
    it 'sets default values' do
      config = described_class.new

      expect(config.enable).to be true
      expect(config.use_test_prof).to be true
      expect(config.fail_on_high_confidence).to be false
      expect(config.enabled_agents).to eq(%i[database factory intent risk])
      expect(config.output_format).to eq(:console)
      expect(config.enforcement_mode).to be false
    end
  end

  describe 'boolean helpers' do
    let(:config) { described_class.new }

    it 'provides enabled? helper' do
      expect(config.enabled?).to be true
      config.enable = false
      expect(config.enabled?).to be false
    end

    it 'provides test_prof_enabled? helper' do
      expect(config.test_prof_enabled?).to be true
      config.use_test_prof = false
      expect(config.test_prof_enabled?).to be false
    end

    it 'provides enforcement_mode? helper' do
      expect(config.enforcement_mode?).to be false
      config.enforcement_mode = true
      expect(config.enforcement_mode?).to be true
    end

    it 'provides json_output? helper' do
      expect(config.json_output?).to be false
      config.output_format = :json
      expect(config.json_output?).to be true
    end

    it 'provides console_output? helper' do
      expect(config.console_output?).to be true
      config.output_format = :json
      expect(config.console_output?).to be false
    end
  end

  describe 'agent management' do
    let(:config) { described_class.new }

    describe '#agent_enabled?' do
      it 'returns true for enabled agents' do
        expect(config.agent_enabled?(:database)).to be true
        expect(config.agent_enabled?('factory')).to be true
      end

      it 'returns false for disabled agents' do
        config.enabled_agents = [:database]
        expect(config.agent_enabled?(:factory)).to be false
      end
    end

    describe '#enable_agent' do
      it 'enables a valid agent' do
        config.enabled_agents = []
        config.enable_agent(:database)
        expect(config.agent_enabled?(:database)).to be true
      end

      it "doesn't duplicate agents" do
        config.enable_agent(:database)
        expect(config.enabled_agents.count(:database)).to eq(1)
      end

      it 'raises error for invalid agent' do
        expect { config.enable_agent(:invalid) }.to raise_error(ArgumentError, /Unknown agent/)
      end
    end

    describe '#disable_agent' do
      it 'disables an agent' do
        config.disable_agent(:database)
        expect(config.agent_enabled?(:database)).to be false
      end
    end
  end

  describe '#output_format=' do
    let(:config) { described_class.new }

    it 'accepts valid output formats' do
      config.output_format = :json
      expect(config.output_format).to eq(:json)

      config.output_format = 'console'
      expect(config.output_format).to eq(:console)
    end

    it 'raises error for invalid output format' do
      expect { config.output_format = :invalid }.to raise_error(ArgumentError, /Invalid output format/)
    end
  end

  describe '#validate!' do
    let(:config) { described_class.new }

    it 'returns true for valid configuration' do
      expect(config.validate!).to be true
    end

    it 'raises error for invalid agents' do
      config.enabled_agents = [:invalid]
      expect { config.validate! }.to raise_error(ArgumentError, /Unregistered agents/)
    end

    it 'raises error for invalid output format' do
      config.instance_variable_set(:@output_format, :invalid)
      expect { config.validate! }.to raise_error(ArgumentError, /Invalid output format/)
    end
  end

  describe '#to_h' do
    it 'returns configuration as hash' do
      config = described_class.new
      hash = config.to_h

      expect(hash).to be_a(Hash)
      expect(hash[:enable]).to be true
      expect(hash[:use_test_prof]).to be true
      expect(hash[:enabled_agents]).to eq(%i[database factory intent risk])
      expect(hash[:available_agents]).to eq(%i[database factory intent risk])
      expect(hash[:output_format]).to eq(:console)
    end
  end

  describe 'agent registry integration' do
    let(:config) { described_class.new }
    let(:mock_ai_agent_class) { double('MockAIAgent', is_a?: true) }
    let(:mock_rule_agent_class) { Class.new(SpecScout::BaseOptimizer) }

    describe '#register_ai_agent' do
      it 'registers AI agent through configuration' do
        config.register_ai_agent(:performance, mock_ai_agent_class)

        expect(config.agent_registry.llm_optimizer_registered?(:performance)).to be true
        expect(config.available_agents).to include(:performance)
      end
    end

    describe '#register_rule_based_agent' do
      it 'registers rule-based agent through configuration' do
        config.register_rule_based_agent(:security, mock_rule_agent_class)

        expect(config.agent_registry.rule_based_optimizer_registered?(:security)).to be true
        expect(config.available_agents).to include(:security)
      end
    end

    describe '#available_agents' do
      it 'returns all registered agent types' do
        config.register_ai_agent(:performance, mock_ai_agent_class)
        config.register_rule_based_agent(:security, mock_rule_agent_class)

        available = config.available_agents
        expect(available).to include(:database, :factory, :intent, :risk, :performance, :security)
      end
    end

    describe '#filtered_enabled_agents' do
      it 'filters enabled agents through registry' do
        config.register_ai_agent(:performance, mock_ai_agent_class)
        config.enabled_agents = %i[database performance nonexistent]

        filtered = config.filtered_enabled_agents
        expect(filtered).to contain_exactly(:database, :performance)
      end
    end

    describe '#enable_agent with custom agents' do
      it 'allows enabling custom agents' do
        config.register_ai_agent(:performance, mock_ai_agent_class)
        config.enable_agent(:performance)

        expect(config.agent_enabled?(:performance)).to be true
      end

      it 'raises error for unregistered agents' do
        expect { config.enable_agent(:nonexistent) }.to raise_error(ArgumentError, /Unknown agent/)
      end
    end
  end
end
