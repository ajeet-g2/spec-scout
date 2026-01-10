# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SpecScout::ContextBuilder do
  let(:context_builder) { described_class.new }
  let(:profile_data) do
    SpecScout::ProfileData.new(
      example_location: 'spec/models/user_spec.rb:42',
      spec_type: :model,
      runtime_ms: 150,
      factories: { user: { strategy: :create, count: 2 } },
      db: { total_queries: 5, inserts: 1, selects: 4 },
      events: { 'factory.create' => 2 },
      metadata: { test_group: 'models' }
    )
  end

  describe '#build_context' do
    context 'with basic profile data' do
      it 'builds base context with formatted data' do
        context = context_builder.build_context(profile_data)

        expect(context).to include(
          spec_location: 'spec/models/user_spec.rb:42',
          spec_type: :model,
          runtime_ms: 150,
          factories: 'user: create (2x)',
          database_usage: 'Total queries: 5, Inserts: 1, Selects: 4',
          events: { 'factory.create' => 2 },
          metadata: { test_group: 'models' }
        )
      end

      it 'includes spec_content as nil when file does not exist' do
        context = context_builder.build_context(profile_data)
        expect(context[:spec_content]).to be_nil
      end
    end

    context 'with provided spec content' do
      let(:spec_content) { 'RSpec.describe User do; end' }

      it 'uses provided spec content' do
        context = context_builder.build_context(profile_data, spec_content)
        expect(context[:spec_content]).to eq(spec_content)
      end
    end

    context 'with agent-specific enhancements' do
      context 'for risk agent' do
        it 'includes model content and callback analysis' do
          context = context_builder.build_context(profile_data, nil, :risk)

          expect(context).to have_key(:model_content)
          expect(context).to have_key(:callback_analysis)
        end
      end

      context 'for intent agent' do
        it 'includes file structure and test dependencies' do
          spec_content = 'RSpec.describe User do; create(:user); end'
          context = context_builder.build_context(profile_data, spec_content, :intent)

          expect(context).to have_key(:file_structure)
          expect(context).to have_key(:test_dependencies)
          expect(context[:file_structure]).to include(
            spec_type_from_path: :model,
            file_name: 'user_spec'
          )
        end
      end

      context 'for factory agent' do
        it 'includes factory definitions and association graph' do
          context = context_builder.build_context(profile_data, nil, :factory)

          expect(context).to have_key(:factory_definitions)
          expect(context).to have_key(:association_graph)
        end
      end

      context 'for database agent' do
        it 'includes related models and optimization opportunities' do
          spec_content = 'User.create(name: "test")'
          context = context_builder.build_context(profile_data, spec_content, :database)

          expect(context).to have_key(:related_models)
          expect(context).to have_key(:optimization_opportunities)
        end
      end
    end
  end

  describe '#format_factories' do
    it 'formats empty factories' do
      result = context_builder.send(:format_factories, {})
      expect(result).to eq('No factories used')
    end

    it 'formats single factory' do
      factories = { user: { strategy: :create, count: 1 } }
      result = context_builder.send(:format_factories, factories)
      expect(result).to eq('user: create (1x)')
    end

    it 'formats multiple factories' do
      factories = {
        user: { strategy: :create, count: 2 },
        post: { strategy: :build_stubbed, count: 1 }
      }
      result = context_builder.send(:format_factories, factories)
      expect(result).to eq('user: create (2x), post: build_stubbed (1x)')
    end
  end

  describe '#format_database_usage' do
    it 'formats empty database usage' do
      result = context_builder.send(:format_database_usage, {})
      expect(result).to eq('No database usage')
    end

    it 'formats complete database usage' do
      db_data = { total_queries: 5, inserts: 1, selects: 4 }
      result = context_builder.send(:format_database_usage, db_data)
      expect(result).to eq('Total queries: 5, Inserts: 1, Selects: 4')
    end

    it 'formats partial database usage' do
      db_data = { total_queries: 3 }
      result = context_builder.send(:format_database_usage, db_data)
      expect(result).to eq('Total queries: 3')
    end
  end

  describe '#extract_model_path' do
    it 'converts model spec path to model path' do
      spec_path = 'spec/models/user_spec.rb'
      result = context_builder.send(:extract_model_path, spec_path)
      expect(result).to eq('app/models/user.rb')
    end

    it 'converts controller spec path to controller path' do
      spec_path = 'spec/controllers/users_controller_spec.rb'
      result = context_builder.send(:extract_model_path, spec_path)
      expect(result).to eq('app/controllers/users_controller.rb')
    end

    it 'returns nil for non-spec paths' do
      result = context_builder.send(:extract_model_path, 'app/models/user.rb')
      expect(result).to be_nil
    end

    it 'returns nil for nil input' do
      result = context_builder.send(:extract_model_path, nil)
      expect(result).to be_nil
    end
  end

  describe '#infer_spec_type_from_path' do
    it 'infers model spec type' do
      result = context_builder.send(:infer_spec_type_from_path, 'spec/models/user_spec.rb')
      expect(result).to eq(:model)
    end

    it 'infers controller spec type' do
      result = context_builder.send(:infer_spec_type_from_path, 'spec/controllers/users_controller_spec.rb')
      expect(result).to eq(:controller)
    end

    it 'infers request spec type' do
      result = context_builder.send(:infer_spec_type_from_path, 'spec/requests/api/users_spec.rb')
      expect(result).to eq(:request)
    end

    it 'returns unknown for unrecognized paths' do
      result = context_builder.send(:infer_spec_type_from_path, 'spec/custom/something_spec.rb')
      expect(result).to eq(:unknown)
    end
  end

  describe '#analyze_test_dependencies' do
    it 'detects database dependencies' do
      spec_content = 'user.save!; User.find(1)'
      result = context_builder.send(:analyze_test_dependencies, spec_content)
      expect(result[:requires_database]).to be true
    end

    it 'detects external service dependencies' do
      spec_content = 'stub_request(:get, "http://example.com")'
      result = context_builder.send(:analyze_test_dependencies, spec_content)
      expect(result[:uses_external_services]).to be true
    end

    it 'detects file operations' do
      spec_content = 'File.read("test.txt")'
      result = context_builder.send(:analyze_test_dependencies, spec_content)
      expect(result[:has_file_operations]).to be true
    end

    it 'detects time travel' do
      spec_content = 'travel_to(1.day.ago)'
      result = context_builder.send(:analyze_test_dependencies, spec_content)
      expect(result[:uses_time_travel]).to be true
    end

    it 'detects JavaScript requirements' do
      spec_content = 'it "works", js: true do'
      result = context_builder.send(:analyze_test_dependencies, spec_content)
      expect(result[:requires_javascript]).to be true
    end

    it 'returns empty hash for nil content' do
      result = context_builder.send(:analyze_test_dependencies, nil)
      expect(result).to eq({})
    end
  end

  describe '#extract_model_dependencies' do
    it 'extracts model class references' do
      spec_content = 'User.create(name: "test"); Post.find(1)'
      result = context_builder.send(:extract_model_dependencies, spec_content)
      expect(result).to include('user', 'post')
    end

    it 'extracts factory references' do
      spec_content = 'create(:user); build(:post)'
      result = context_builder.send(:extract_model_dependencies, spec_content)
      expect(result).to include('user', 'post')
    end

    it 'returns empty array for nil content' do
      result = context_builder.send(:extract_model_dependencies, nil)
      expect(result).to eq([])
    end
  end

  describe '#identify_optimization_patterns' do
    it 'identifies read-only test pattern' do
      read_only_data = SpecScout::ProfileData.new(
        db: { inserts: 0, selects: 3, total_queries: 3 },
        factories: {}
      )
      result = context_builder.send(:identify_optimization_patterns, read_only_data)
      expect(result).to include('read_only_test')
    end

    it 'identifies high query count pattern' do
      high_query_data = SpecScout::ProfileData.new(
        db: { total_queries: 15, inserts: 5, selects: 10 },
        factories: {}
      )
      result = context_builder.send(:identify_optimization_patterns, high_query_data)
      expect(result).to include('high_query_count')
    end

    it 'identifies bulk factory creation pattern' do
      bulk_factory_data = SpecScout::ProfileData.new(
        db: {},
        factories: { user: { strategy: :create, count: 5 } }
      )
      result = context_builder.send(:identify_optimization_patterns, bulk_factory_data)
      expect(result).to include('bulk_factory_creation')
    end
  end
end
