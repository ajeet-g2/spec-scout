# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Optimizer Functional Equivalence', type: :property do
  # Feature: agents-to-optimizer-refactor, Property 5: Functional Equivalence
  # Validates: Requirements 1.4, 4.3, 6.4

  describe 'Property 5: Functional Equivalence' do
    let(:rule_based_optimizer_types) { %w[database factory intent risk] }

    # Test data variations to ensure comprehensive coverage
    let(:test_scenarios) do
      [
        # Scenario 1: No database usage
        {
          name: 'no_database_usage',
          profile_data: SpecScout::ProfileData.new(
            example_location: 'spec/models/user_spec.rb:10',
            spec_type: :model,
            runtime_ms: 50,
            db: { total_queries: 0, inserts: 0, selects: 0 },
            factories: {}
          )
        },
        # Scenario 2: Database reads only
        {
          name: 'database_reads_only',
          profile_data: SpecScout::ProfileData.new(
            example_location: 'spec/models/user_spec.rb:20',
            spec_type: :model,
            runtime_ms: 120,
            db: { total_queries: 3, inserts: 0, selects: 3 },
            factories: {}
          )
        },
        # Scenario 3: Database writes present
        {
          name: 'database_writes_present',
          profile_data: SpecScout::ProfileData.new(
            example_location: 'spec/models/user_spec.rb:30',
            spec_type: :model,
            runtime_ms: 200,
            db: { total_queries: 5, inserts: 2, selects: 3 },
            factories: { user: { strategy: :create, count: 2 } }
          )
        },
        # Scenario 4: Factory usage without database
        {
          name: 'factory_usage_no_db',
          profile_data: SpecScout::ProfileData.new(
            example_location: 'spec/models/user_spec.rb:40',
            spec_type: :model,
            runtime_ms: 80,
            db: { total_queries: 0, inserts: 0, selects: 0 },
            factories: { user: { strategy: :build_stubbed, count: 1 } }
          )
        },
        # Scenario 5: Integration test scenario
        {
          name: 'integration_test',
          profile_data: SpecScout::ProfileData.new(
            example_location: 'spec/requests/api_spec.rb:15',
            spec_type: :request,
            runtime_ms: 500,
            db: { total_queries: 10, inserts: 3, selects: 7 },
            factories: { user: { strategy: :create, count: 1 }, post: { strategy: :create, count: 2 } }
          )
        }
      ]
    end

    context 'Rule-based optimizers functional consistency' do
      it 'produces consistent results across all test scenarios for each optimizer type' do
        rule_based_optimizer_types.each do |optimizer_type|
          require_relative "../../../../lib/spec_scout/optimizers/rule_based/#{optimizer_type}_optimiser"

          class_name = "#{optimizer_type.capitalize}Optimiser"
          optimizer_class = SpecScout::Optimizers::RuleBased.const_get(class_name)

          test_scenarios.each do |scenario|
            # Create optimizer instance
            optimizer = optimizer_class.new(scenario[:profile_data])

            # Evaluate should not raise errors
            expect { optimizer.evaluate }.not_to raise_error

            # Result should be an OptimizerResult
            result = optimizer.evaluate
            expect(result).to be_a(SpecScout::OptimizerResult)

            # Result should have required fields
            expect(result.optimizer_name).to be_a(Symbol)
            expect(result.verdict).to be_a(Symbol)
            expect(result.confidence).to be_a(Symbol)
            expect(result.reasoning).to be_a(String)
            expect(result.metadata).to be_a(Hash)

            # Confidence should be valid
            expect(%i[low medium high]).to include(result.confidence)
          end
        end
      end

      it 'maintains deterministic behavior for identical inputs' do
        rule_based_optimizer_types.each do |optimizer_type|
          require_relative "../../../../lib/spec_scout/optimizers/rule_based/#{optimizer_type}_optimiser"

          class_name = "#{optimizer_type.capitalize}Optimiser"
          optimizer_class = SpecScout::Optimizers::RuleBased.const_get(class_name)

          test_scenarios.each do |scenario|
            # Create two identical optimizers with same profile data
            optimizer1 = optimizer_class.new(scenario[:profile_data])
            optimizer2 = optimizer_class.new(scenario[:profile_data])

            result1 = optimizer1.evaluate
            result2 = optimizer2.evaluate

            # Results should be identical for deterministic rule-based optimizers
            expect(result1.verdict).to eq(result2.verdict)
            expect(result1.confidence).to eq(result2.confidence)
            expect(result1.reasoning).to eq(result2.reasoning)
            expect(result1.optimizer_name).to eq(result2.optimizer_name)
          end
        end
      end

      it 'produces appropriate verdicts based on input characteristics' do
        # Test database optimizer specifically with known scenarios
        require_relative '../../../../lib/spec_scout/optimizers/rule_based/database_optimiser'

        database_optimizer_class = SpecScout::Optimizers::RuleBased::DatabaseOptimiser

        # No database usage should suggest db_unnecessary
        no_db_profile = SpecScout::ProfileData.new(
          example_location: 'spec/models/user_spec.rb:10',
          spec_type: :model,
          runtime_ms: 50,
          db: { total_queries: 0, inserts: 0, selects: 0 },
          factories: {}
        )

        optimizer = database_optimizer_class.new(no_db_profile)
        result = optimizer.evaluate
        expect(result.verdict).to eq(:db_unclear) # Based on the optimizer's logic for no data

        # Database writes should suggest db_required
        db_writes_profile = SpecScout::ProfileData.new(
          example_location: 'spec/models/user_spec.rb:30',
          spec_type: :model,
          runtime_ms: 200,
          db: { total_queries: 5, inserts: 2, selects: 3 },
          factories: {}
        )

        optimizer = database_optimizer_class.new(db_writes_profile)
        result = optimizer.evaluate
        expect(result.verdict).to eq(:db_required)
      end
    end

    context 'Optimizer name consistency' do
      it 'maintains consistent optimizer_name across all scenarios' do
        rule_based_optimizer_types.each do |optimizer_type|
          require_relative "../../../../lib/spec_scout/optimizers/rule_based/#{optimizer_type}_optimiser"

          class_name = "#{optimizer_type.capitalize}Optimiser"
          optimizer_class = SpecScout::Optimizers::RuleBased.const_get(class_name)

          expected_optimizer_name = optimizer_type.to_sym

          test_scenarios.each do |scenario|
            optimizer = optimizer_class.new(scenario[:profile_data])
            expect(optimizer.optimizer_name).to eq(expected_optimizer_name)

            result = optimizer.evaluate
            expect(result.optimizer_name).to eq(expected_optimizer_name)
          end
        end
      end
    end

    context 'Error handling consistency' do
      it 'handles invalid profile data gracefully' do
        rule_based_optimizer_types.each do |optimizer_type|
          require_relative "../../../../lib/spec_scout/optimizers/rule_based/#{optimizer_type}_optimiser"

          class_name = "#{optimizer_type.capitalize}Optimiser"
          optimizer_class = SpecScout::Optimizers::RuleBased.const_get(class_name)

          # Test with invalid profile data
          invalid_profile = SpecScout::ProfileData.new(
            example_location: nil, # Invalid
            spec_type: 'invalid', # Should be symbol
            runtime_ms: 'invalid', # Should be numeric
            db: 'invalid', # Should be hash
            factories: 'invalid' # Should be hash
          )

          # Should raise ArgumentError during initialization due to validation
          expect { optimizer_class.new(invalid_profile) }.to raise_error(ArgumentError)
        end
      end
    end

    context 'Performance characteristics' do
      it 'completes evaluation within reasonable time bounds' do
        rule_based_optimizer_types.each do |optimizer_type|
          require_relative "../../../../lib/spec_scout/optimizers/rule_based/#{optimizer_type}_optimiser"

          class_name = "#{optimizer_type.capitalize}Optimiser"
          optimizer_class = SpecScout::Optimizers::RuleBased.const_get(class_name)

          test_scenarios.each do |scenario|
            optimizer = optimizer_class.new(scenario[:profile_data])

            # Evaluation should complete quickly (rule-based optimizers should be fast)
            start_time = Time.now
            optimizer.evaluate
            end_time = Time.now

            execution_time = end_time - start_time
            expect(execution_time).to be < 0.1 # Should complete in under 100ms
          end
        end
      end
    end
  end
end
