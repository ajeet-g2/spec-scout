# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Optimizer Interface Preservation', type: :property do
  # Feature: agents-to-optimizer-refactor, Property 3: Interface Preservation
  # Validates: Requirements 3.5, 4.4

  describe 'Property 3: Interface Preservation' do
    let(:llm_optimizer_types) { %w[database factory intent risk] }
    let(:rule_based_optimizer_types) { %w[database factory intent risk] }

    context 'LLM-based optimizers' do
      it 'preserves class names and module namespaces for all LLM optimizers' do
        llm_optimizer_types.each do |optimizer_type|
          # Load the optimizer class
          require_relative "../../../../lib/spec_scout/optimizers/llm_based/#{optimizer_type}_optimiser"

          # Verify the class exists in the expected namespace
          class_name = "#{optimizer_type.capitalize}Optimiser"
          expect(SpecScout::Optimizers::LlmBased.const_defined?(class_name)).to be true

          optimizer_class = SpecScout::Optimizers::LlmBased.const_get(class_name)

          # Verify it inherits from BaseLlmOptimizer
          expect(optimizer_class.superclass).to eq(SpecScout::BaseLlmOptimizer)

          # Verify it has the expected interface methods
          expect(optimizer_class.instance_methods).to include(:analyze)
          expect(optimizer_class.instance_methods).to include(:optimizer_name)

          # Verify protected methods exist
          expect(optimizer_class.protected_instance_methods).to include(:get_prompt_template)
          expect(optimizer_class.protected_instance_methods).to include(:build_context)
        end
      end

      it 'maintains consistent method signatures across all LLM optimizers' do
        llm_optimizer_types.each do |optimizer_type|
          require_relative "../../../../lib/spec_scout/optimizers/llm_based/#{optimizer_type}_optimiser"

          class_name = "#{optimizer_type.capitalize}Optimiser"
          optimizer_class = SpecScout::Optimizers::LlmBased.const_get(class_name)

          # Check analyze method signature (from BaseLlmOptimizer)
          analyze_method = optimizer_class.instance_method(:analyze)
          expect(analyze_method.arity).to be_between(-3, 2) # analyze(profile_data, spec_content = nil)

          # Check get_prompt_template method exists and has correct arity
          template_method = optimizer_class.instance_method(:get_prompt_template)
          expect(template_method.arity).to eq(0)
        end
      end
    end

    context 'Rule-based optimizers' do
      it 'preserves class names and module namespaces for all rule-based optimizers' do
        rule_based_optimizer_types.each do |optimizer_type|
          # Load the optimizer class
          require_relative "../../../../lib/spec_scout/optimizers/rule_based/#{optimizer_type}_optimiser"

          # Verify the class exists in the expected namespace
          class_name = "#{optimizer_type.capitalize}Optimiser"
          expect(SpecScout::Optimizers::RuleBased.const_defined?(class_name)).to be true

          optimizer_class = SpecScout::Optimizers::RuleBased.const_get(class_name)

          # Verify it inherits from BaseOptimizer
          expect(optimizer_class.superclass).to eq(SpecScout::BaseOptimizer)

          # Verify it has the expected interface methods
          expect(optimizer_class.instance_methods).to include(:evaluate)
          expect(optimizer_class.instance_methods).to include(:optimizer_name)
        end
      end

      it 'maintains consistent method signatures across all rule-based optimizers' do
        rule_based_optimizer_types.each do |optimizer_type|
          require_relative "../../../../lib/spec_scout/optimizers/rule_based/#{optimizer_type}_optimiser"

          class_name = "#{optimizer_type.capitalize}Optimiser"
          optimizer_class = SpecScout::Optimizers::RuleBased.const_get(class_name)

          # Check evaluate method signature
          evaluate_method = optimizer_class.instance_method(:evaluate)
          expect(evaluate_method.arity).to eq(0)

          # Check optimizer_name method signature
          optimizer_name_method = optimizer_class.instance_method(:optimizer_name)
          expect(optimizer_name_method.arity).to eq(0)
        end
      end
    end

    context 'Cross-optimizer consistency' do
      it 'ensures all optimizers can be instantiated with proper dependencies' do
        # Test rule-based optimizers (simpler instantiation)
        rule_based_optimizer_types.each do |optimizer_type|
          require_relative "../../../../lib/spec_scout/optimizers/rule_based/#{optimizer_type}_optimiser"

          class_name = "#{optimizer_type.capitalize}Optimiser"
          optimizer_class = SpecScout::Optimizers::RuleBased.const_get(class_name)

          # Create real ProfileData object
          profile_data = SpecScout::ProfileData.new(
            example_location: 'spec/example_spec.rb:42',
            spec_type: :model,
            runtime_ms: 100,
            db: { total_queries: 0, inserts: 0, selects: 0 },
            factories: {}
          )

          # Should be able to instantiate
          expect { optimizer_class.new(profile_data) }.not_to raise_error
        end
      end

      it 'maintains optimizer_name method consistency across all optimizers' do
        all_optimizers = []

        # Collect rule-based optimizers
        rule_based_optimizer_types.each do |optimizer_type|
          require_relative "../../../../lib/spec_scout/optimizers/rule_based/#{optimizer_type}_optimiser"
          class_name = "#{optimizer_type.capitalize}Optimiser"
          optimizer_class = SpecScout::Optimizers::RuleBased.const_get(class_name)

          profile_data = SpecScout::ProfileData.new(
            example_location: 'spec/example_spec.rb:42',
            spec_type: :model,
            runtime_ms: 100,
            db: { total_queries: 0 },
            factories: {}
          )

          optimizer_instance = optimizer_class.new(profile_data)
          all_optimizers << optimizer_instance
        end

        # Verify all optimizer names are symbols and follow expected pattern
        all_optimizers.each do |optimizer|
          expect(optimizer.optimizer_name).to be_a(Symbol)
          expect(optimizer.optimizer_name.to_s).to match(/^(database|factory|intent|risk)$/)
        end
      end
    end
  end
end
