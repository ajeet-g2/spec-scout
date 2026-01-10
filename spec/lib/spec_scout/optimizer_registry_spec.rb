# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SpecScout::OptimizerRegistry do
  subject(:registry) { described_class.new }

  describe '#initialize' do
    it 'registers default rule-based optimizers' do
      expect(registry.rule_based_optimizer_registered?(:database)).to be true
      expect(registry.rule_based_optimizer_registered?(:factory)).to be true
      expect(registry.rule_based_optimizer_registered?(:intent)).to be true
      expect(registry.rule_based_optimizer_registered?(:risk)).to be true
    end

    it 'starts with LLM optimizers registered' do
      expect(registry.llm_optimizer_types).to contain_exactly(:database, :factory, :intent, :risk)
    end
  end

  describe '#register_llm_optimizer' do
    let(:mock_llm_optimizer_class) { double('MockLLMOptimizer', is_a?: true) }

    it 'registers an LLM optimizer' do
      registry.register_llm_optimizer(:database, mock_llm_optimizer_class)

      expect(registry.llm_optimizer_registered?(:database)).to be true
      expect(registry.get_llm_optimizer(:database)).to eq(mock_llm_optimizer_class)
    end

    it 'accepts string optimizer types' do
      registry.register_llm_optimizer('database', mock_llm_optimizer_class)

      expect(registry.llm_optimizer_registered?(:database)).to be true
    end

    it 'accepts custom optimizer types' do
      registry.register_llm_optimizer(:custom, mock_llm_optimizer_class)

      expect(registry.llm_optimizer_registered?(:custom)).to be true
    end

    it 'raises error for non-class optimizer' do
      expect do
        registry.register_llm_optimizer(:database, 'not a class')
      end.to raise_error(ArgumentError, /LLM optimizer must be a Class/)
    end
  end

  describe '#register_rule_based_optimizer' do
    let(:mock_rule_optimizer_class) { Class.new(SpecScout::BaseOptimizer) }

    it 'registers a rule-based optimizer' do
      registry.register_rule_based_optimizer(:custom, mock_rule_optimizer_class)

      expect(registry.rule_based_optimizer_registered?(:custom)).to be true
      expect(registry.get_rule_based_optimizer(:custom)).to eq(mock_rule_optimizer_class)
    end

    it 'raises error for non-BaseOptimizer class' do
      non_base_optimizer_class = Class.new

      expect do
        registry.register_rule_based_optimizer(:custom, non_base_optimizer_class)
      end.to raise_error(ArgumentError, /must inherit from BaseOptimizer/)
    end
  end

  describe '#llm_optimizer_registered?' do
    let(:mock_llm_optimizer_class) { double('MockLLMOptimizer', is_a?: true) }

    it 'returns true for registered LLM optimizers' do
      registry.register_llm_optimizer(:database, mock_llm_optimizer_class)

      expect(registry.llm_optimizer_registered?(:database)).to be true
    end

    it 'returns false for unregistered LLM optimizers' do
      expect(registry.llm_optimizer_registered?(:nonexistent)).to be false
    end
  end

  describe '#rule_based_optimizer_registered?' do
    it 'returns true for default rule-based optimizers' do
      expect(registry.rule_based_optimizer_registered?(:database)).to be true
    end

    it 'returns false for unregistered rule-based optimizers' do
      expect(registry.rule_based_optimizer_registered?(:nonexistent)).to be false
    end
  end

  describe '#optimizer_registered?' do
    let(:mock_llm_optimizer_class) { double('MockLLMOptimizer', is_a?: true) }

    it 'returns true for rule-based optimizers' do
      expect(registry.optimizer_registered?(:database)).to be true
    end

    it 'returns true for LLM optimizers' do
      registry.register_llm_optimizer(:custom, mock_llm_optimizer_class)

      expect(registry.optimizer_registered?(:custom)).to be true
    end

    it 'returns false for unregistered optimizers' do
      expect(registry.optimizer_registered?(:nonexistent)).to be false
    end
  end

  describe '#enabled_optimizers' do
    let(:mock_llm_optimizer_class) { double('MockLLMOptimizer', is_a?: true) }

    before do
      registry.register_llm_optimizer(:database, mock_llm_optimizer_class)
    end

    it 'filters enabled optimizers to only registered ones' do
      enabled_list = %i[database factory nonexistent intent]

      result = registry.enabled_optimizers(enabled_list)

      expect(result).to contain_exactly(:database, :factory, :intent)
    end
  end

  describe '#all_optimizer_types' do
    let(:mock_llm_optimizer_class) { double('MockLLMOptimizer', is_a?: true) }

    before do
      registry.register_llm_optimizer(:database, mock_llm_optimizer_class)
    end

    it 'returns all registered optimizer types' do
      result = registry.all_optimizer_types

      expect(result).to include(:database, :factory, :intent, :risk)
    end

    it 'does not duplicate optimizer types registered as both LLM and rule-based' do
      result = registry.all_optimizer_types

      expect(result.count(:database)).to eq(1)
    end
  end

  describe '#clear_all_optimizers' do
    let(:mock_llm_optimizer_class) { double('MockLLMOptimizer', is_a?: true) }

    before do
      registry.register_llm_optimizer(:database, mock_llm_optimizer_class)
    end

    it 'clears all registered optimizers' do
      registry.clear_all_optimizers

      expect(registry.llm_optimizer_types).to be_empty
      expect(registry.rule_based_optimizer_types).to be_empty
    end
  end

  describe '#reset_to_defaults' do
    let(:mock_llm_optimizer_class) { double('MockLLMOptimizer', is_a?: true) }

    before do
      registry.register_llm_optimizer(:database, mock_llm_optimizer_class)
      registry.clear_all_optimizers
    end

    it 'resets to default rule-based and LLM optimizers' do
      registry.reset_to_defaults

      expect(registry.rule_based_optimizer_registered?(:database)).to be true
      expect(registry.rule_based_optimizer_registered?(:factory)).to be true
      expect(registry.rule_based_optimizer_registered?(:intent)).to be true
      expect(registry.rule_based_optimizer_registered?(:risk)).to be true
      expect(registry.llm_optimizer_types).to contain_exactly(:database, :factory, :intent, :risk)
    end
  end

  describe 'custom optimizer support' do
    let(:mock_llm_optimizer_class) { double('MockLLMOptimizer', is_a?: true) }
    let(:mock_rule_optimizer_class) { Class.new(SpecScout::BaseOptimizer) }

    it 'supports registering custom LLM optimizers' do
      registry.register_llm_optimizer(:performance, mock_llm_optimizer_class)
      registry.register_llm_optimizer(:security, mock_llm_optimizer_class)

      expect(registry.llm_optimizer_registered?(:performance)).to be true
      expect(registry.llm_optimizer_registered?(:security)).to be true
      expect(registry.llm_optimizer_types).to include(:performance, :security)
    end

    it 'supports registering custom rule-based optimizers' do
      registry.register_rule_based_optimizer(:performance, mock_rule_optimizer_class)
      registry.register_rule_based_optimizer(:security, mock_rule_optimizer_class)

      expect(registry.rule_based_optimizer_registered?(:performance)).to be true
      expect(registry.rule_based_optimizer_registered?(:security)).to be true
      expect(registry.rule_based_optimizer_types).to include(:performance, :security)
    end

    it 'supports mixed custom and default optimizers' do
      registry.register_llm_optimizer(:performance, mock_llm_optimizer_class)
      registry.register_rule_based_optimizer(:security, mock_rule_optimizer_class)

      all_types = registry.all_optimizer_types
      expect(all_types).to include(:database, :factory, :intent, :risk, :performance, :security)
    end

    it 'filters enabled optimizers correctly with custom optimizers' do
      registry.register_llm_optimizer(:performance, mock_llm_optimizer_class)
      registry.register_rule_based_optimizer(:security, mock_rule_optimizer_class)

      enabled_list = %i[database performance security nonexistent]
      result = registry.enabled_optimizers(enabled_list)

      expect(result).to contain_exactly(:database, :performance, :security)
    end
  end

  describe 'dynamic optimizer management' do
    let(:mock_llm_optimizer_class) { double('MockLLMOptimizer', is_a?: true) }
    let(:mock_rule_optimizer_class) { Class.new(SpecScout::BaseOptimizer) }

    it 'allows overriding default optimizers with LLM versions' do
      # Register LLM version of database optimizer
      registry.register_llm_optimizer(:database, mock_llm_optimizer_class)

      expect(registry.llm_optimizer_registered?(:database)).to be true
      expect(registry.rule_based_optimizer_registered?(:database)).to be true
      expect(registry.optimizer_registered?(:database)).to be true
    end

    it 'maintains separate registries for LLM and rule-based optimizers' do
      registry.register_llm_optimizer(:database, mock_llm_optimizer_class)

      expect(registry.get_llm_optimizer(:database)).to eq(mock_llm_optimizer_class)
      expect(registry.get_rule_based_optimizer(:database)).to eq(SpecScout::Optimizers::RuleBased::DatabaseOptimiser)
      expect(registry.get_llm_optimizer(:database)).not_to eq(registry.get_rule_based_optimizer(:database))
    end

    it 'supports runtime optimizer registration and deregistration' do
      # Start with defaults
      expect(registry.all_optimizer_types.size).to eq(4)

      # Add custom optimizers
      registry.register_llm_optimizer(:custom1, mock_llm_optimizer_class)
      registry.register_rule_based_optimizer(:custom2, mock_rule_optimizer_class)
      expect(registry.all_optimizer_types.size).to eq(6)

      # Clear and reset
      registry.clear_all_optimizers
      expect(registry.all_optimizer_types.size).to eq(0)

      registry.reset_to_defaults
      expect(registry.all_optimizer_types.size).to eq(4)
    end
  end

  # Task 7.1: Test optimizer registry can discover all optimizers after reorganization
  describe 'optimizer discovery after reorganization' do
    it 'discovers all expected rule-based optimizers' do
      expected_rule_based_optimizers = %i[database factory intent risk]

      expect(registry.rule_based_optimizer_types).to contain_exactly(*expected_rule_based_optimizers)

      expected_rule_based_optimizers.each do |optimizer_type|
        expect(registry.rule_based_optimizer_registered?(optimizer_type)).to be true
        expect(registry.get_rule_based_optimizer(optimizer_type)).not_to be_nil
      end
    end

    it 'discovers all expected LLM optimizers' do
      expected_llm_optimizers = %i[database factory intent risk]

      expect(registry.llm_optimizer_types).to contain_exactly(*expected_llm_optimizers)

      expected_llm_optimizers.each do |optimizer_type|
        expect(registry.llm_optimizer_registered?(optimizer_type)).to be true
        expect(registry.get_llm_optimizer(optimizer_type)).not_to be_nil
      end
    end

    it 'discovers the same number of optimizers as before reorganization' do
      # Should have 4 rule-based optimizers and 4 LLM optimizers
      expect(registry.rule_based_optimizer_types.size).to eq(4)
      expect(registry.llm_optimizer_types.size).to eq(4)
      expect(registry.all_optimizer_types.size).to eq(4) # Unique types
    end

    it 'can access all optimizer classes from their new locations' do
      # Verify rule-based optimizers can be instantiated
      %i[database factory intent risk].each do |optimizer_type|
        optimizer_class = registry.get_rule_based_optimizer(optimizer_type)
        expect(optimizer_class).to be_a(Class)
        expect(optimizer_class.ancestors).to include(SpecScout::BaseOptimizer)

        # Verify LLM optimizers can be instantiated
        optimizer_class = registry.get_llm_optimizer(optimizer_type)
        expect(optimizer_class).to be_a(Class)
        expect(optimizer_class.ancestors).to include(SpecScout::BaseLlmOptimizer)
      end
    end

    it 'maintains correct optimizer class names after reorganization' do
      # Rule-based optimizers should maintain their original class names
      expect(registry.get_rule_based_optimizer(:database)).to eq(SpecScout::Optimizers::RuleBased::DatabaseOptimiser)
      expect(registry.get_rule_based_optimizer(:factory)).to eq(SpecScout::Optimizers::RuleBased::FactoryOptimiser)
      expect(registry.get_rule_based_optimizer(:intent)).to eq(SpecScout::Optimizers::RuleBased::IntentOptimiser)
      expect(registry.get_rule_based_optimizer(:risk)).to eq(SpecScout::Optimizers::RuleBased::RiskOptimiser)

      # LLM optimizers should maintain their original class names (with LLM suffix)
      expect(registry.get_llm_optimizer(:database)).to eq(SpecScout::Optimizers::LlmBased::DatabaseOptimiser)
      expect(registry.get_llm_optimizer(:factory)).to eq(SpecScout::Optimizers::LlmBased::FactoryOptimiser)
      expect(registry.get_llm_optimizer(:intent)).to eq(SpecScout::Optimizers::LlmBased::IntentOptimiser)
      expect(registry.get_llm_optimizer(:risk)).to eq(SpecScout::Optimizers::LlmBased::RiskOptimiser)
    end
  end

  # Task 7.2: Test optimizer registry public interface preservation
  describe 'public interface preservation after reorganization' do
    let(:mock_llm_optimizer_class) { double('MockLLMOptimizer', is_a?: true) }
    let(:mock_rule_optimizer_class) { Class.new(SpecScout::BaseOptimizer) }

    describe 'optimizer registration methods' do
      it 'register_llm_optimizer works identically to before reorganization' do
        expect { registry.register_llm_optimizer(:custom, mock_llm_optimizer_class) }.not_to raise_error
        expect(registry.llm_optimizer_registered?(:custom)).to be true
        expect(registry.get_llm_optimizer(:custom)).to eq(mock_llm_optimizer_class)
      end

      it 'register_rule_based_optimizer works identically to before reorganization' do
        expect { registry.register_rule_based_optimizer(:custom, mock_rule_optimizer_class) }.not_to raise_error
        expect(registry.rule_based_optimizer_registered?(:custom)).to be true
        expect(registry.get_rule_based_optimizer(:custom)).to eq(mock_rule_optimizer_class)
      end
    end

    describe 'optimizer retrieval methods' do
      it 'get_llm_optimizer returns correct classes after reorganization' do
        %i[database factory intent risk].each do |optimizer_type|
          optimizer_class = registry.get_llm_optimizer(optimizer_type)
          expect(optimizer_class).to be_a(Class)
          expect(optimizer_class.name).to include('Optimiser')
        end
      end

      it 'get_rule_based_optimizer returns correct classes after reorganization' do
        %i[database factory intent risk].each do |optimizer_type|
          optimizer_class = registry.get_rule_based_optimizer(optimizer_type)
          expect(optimizer_class).to be_a(Class)
          expect(optimizer_class.ancestors).to include(SpecScout::BaseOptimizer)
        end
      end

      it 'returns nil for unregistered optimizers' do
        expect(registry.get_llm_optimizer(:nonexistent)).to be_nil
        expect(registry.get_rule_based_optimizer(:nonexistent)).to be_nil
      end
    end

    describe 'optimizer checking methods' do
      it 'llm_optimizer_registered? works correctly after reorganization' do
        %i[database factory intent risk].each do |optimizer_type|
          expect(registry.llm_optimizer_registered?(optimizer_type)).to be true
        end
        expect(registry.llm_optimizer_registered?(:nonexistent)).to be false
      end

      it 'rule_based_optimizer_registered? works correctly after reorganization' do
        %i[database factory intent risk].each do |optimizer_type|
          expect(registry.rule_based_optimizer_registered?(optimizer_type)).to be true
        end
        expect(registry.rule_based_optimizer_registered?(:nonexistent)).to be false
      end

      it 'optimizer_registered? works correctly for both optimizer types' do
        %i[database factory intent risk].each do |optimizer_type|
          expect(registry.optimizer_registered?(optimizer_type)).to be true
        end
        expect(registry.optimizer_registered?(:nonexistent)).to be false
      end
    end

    describe 'optimizer listing methods' do
      it 'llm_optimizer_types returns all LLM optimizer types' do
        types = registry.llm_optimizer_types
        expect(types).to be_an(Array)
        expect(types).to contain_exactly(:database, :factory, :intent, :risk)
      end

      it 'rule_based_optimizer_types returns all rule-based optimizer types' do
        types = registry.rule_based_optimizer_types
        expect(types).to be_an(Array)
        expect(types).to contain_exactly(:database, :factory, :intent, :risk)
      end

      it 'all_optimizer_types returns unique optimizer types' do
        types = registry.all_optimizer_types
        expect(types).to be_an(Array)
        expect(types).to contain_exactly(:database, :factory, :intent, :risk)
        expect(types.uniq.size).to eq(types.size) # No duplicates
      end
    end

    describe 'optimizer filtering methods' do
      it 'enabled_optimizers filters correctly after reorganization' do
        enabled_list = %i[database factory nonexistent custom]
        registry.register_llm_optimizer(:custom, mock_llm_optimizer_class)

        result = registry.enabled_optimizers(enabled_list)
        expect(result).to contain_exactly(:database, :factory, :custom)
      end

      it 'enabled_optimizers handles empty input' do
        result = registry.enabled_optimizers([])
        expect(result).to eq([])
      end

      it 'enabled_optimizers handles all unregistered optimizers' do
        result = registry.enabled_optimizers(%i[nonexistent1 nonexistent2])
        expect(result).to eq([])
      end
    end

    describe 'registry management methods' do
      it 'clear_all_optimizers works correctly after reorganization' do
        registry.clear_all_optimizers

        expect(registry.llm_optimizer_types).to be_empty
        expect(registry.rule_based_optimizer_types).to be_empty
        expect(registry.all_optimizer_types).to be_empty
      end

      it 'reset_to_defaults restores all default optimizers after reorganization' do
        registry.clear_all_optimizers
        registry.reset_to_defaults

        expect(registry.llm_optimizer_types).to contain_exactly(:database, :factory, :intent, :risk)
        expect(registry.rule_based_optimizer_types).to contain_exactly(:database, :factory, :intent, :risk)

        # Verify optimizers are actually accessible
        %i[database factory intent risk].each do |optimizer_type|
          expect(registry.get_llm_optimizer(optimizer_type)).not_to be_nil
          expect(registry.get_rule_based_optimizer(optimizer_type)).not_to be_nil
        end
      end
    end

    describe 'method signature compatibility' do
      it 'all public methods accept the same parameter types as before' do
        # String and symbol optimizer types should work
        registry.register_llm_optimizer('string_type', mock_llm_optimizer_class)
        registry.register_llm_optimizer(:symbol_type, mock_llm_optimizer_class)

        expect(registry.llm_optimizer_registered?('string_type')).to be true
        expect(registry.llm_optimizer_registered?(:symbol_type)).to be true
        expect(registry.get_llm_optimizer('string_type')).to eq(mock_llm_optimizer_class)
        expect(registry.get_llm_optimizer(:symbol_type)).to eq(mock_llm_optimizer_class)
      end

      it 'maintains error handling behavior' do
        expect { registry.register_llm_optimizer(:test, 'not_a_class') }
          .to raise_error(ArgumentError, /LLM optimizer must be a Class/)

        expect { registry.register_rule_based_optimizer(:test, Class.new) }
          .to raise_error(ArgumentError, /must inherit from BaseOptimizer/)
      end
    end
  end
end
