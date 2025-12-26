# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SpecScout::Agents::IntentAgent do
  let(:runtime_ms) { 15 }
  let(:factories_data) { {} }
  let(:db_data) { {} }

  describe '#evaluate' do
    context 'when no location data is available' do
      let(:profile_data) do
        SpecScout::ProfileData.new(
          example_location: '',
          spec_type: :model,
          runtime_ms: runtime_ms,
          factories: factories_data,
          db: db_data,
          events: {},
          metadata: {}
        )
      end

      it 'returns unclear intent with low confidence' do
        agent = described_class.new(profile_data)
        result = agent.evaluate

        expect(result.verdict).to eq(:intent_unclear)
        expect(result.confidence).to eq(:low)
        expect(result.reasoning).to include('No spec location data available')
        expect(result.metadata[:no_data]).to be true
      end
    end

    context 'with strong unit test signals' do
      let(:profile_data) do
        SpecScout::ProfileData.new(
          example_location: 'spec/models/user_spec.rb:42',
          spec_type: :model,
          runtime_ms: 5,
          factories: { user: { strategy: :build_stubbed, count: 1 } },
          db: { inserts: 0, selects: 1, total_queries: 1 },
          events: {},
          metadata: {}
        )
      end

      it 'identifies unit test behavior with high confidence' do
        agent = described_class.new(profile_data)
        result = agent.evaluate

        expect(result.verdict).to eq(:unit_test_behavior)
        expect(result.confidence).to eq(:high)
        expect(result.reasoning).to include('Strong unit test behavior detected')
        expect(result.metadata[:file_location_signal]).to eq(:unit_test_location)
        expect(result.metadata[:runtime_behavior_signal]).to eq(:fast_execution)
        expect(result.metadata[:database_usage_signal]).to eq(:minimal_database)
        expect(result.metadata[:factory_usage_signal]).to eq(:minimal_factories)
      end
    end

    context 'with strong integration test signals' do
      let(:profile_data) do
        SpecScout::ProfileData.new(
          example_location: 'spec/features/user_registration_spec.rb:15',
          spec_type: :model,
          runtime_ms: 250,
          factories: {
            user: { strategy: :create, count: 3 },
            post: { strategy: :create, count: 5 }
          },
          db: { inserts: 8, selects: 15, total_queries: 23 },
          events: {},
          metadata: {}
        )
      end

      it 'identifies integration test behavior with high confidence' do
        agent = described_class.new(profile_data)
        result = agent.evaluate

        expect(result.verdict).to eq(:integration_test_behavior)
        expect(result.confidence).to eq(:high)
        expect(result.reasoning).to include('Strong integration test behavior detected')
        expect(result.metadata[:file_location_signal]).to eq(:integration_test_location)
        expect(result.metadata[:runtime_behavior_signal]).to eq(:slow_execution)
        expect(result.metadata[:database_usage_signal]).to eq(:heavy_database)
        expect(result.metadata[:factory_usage_signal]).to eq(:heavy_factories)
      end
    end

    context 'with mixed signals favoring unit test' do
      let(:profile_data) do
        SpecScout::ProfileData.new(
          example_location: 'spec/models/user_spec.rb:42',
          spec_type: :model,
          runtime_ms: 50, # moderate execution
          factories: { user: { strategy: :create, count: 2 } }, # moderate factories
          db: { inserts: 0, selects: 1, total_queries: 1 }, # minimal database
          events: {},
          metadata: {}
        )
      end

      it 'identifies likely unit test behavior with medium confidence' do
        agent = described_class.new(profile_data)
        result = agent.evaluate

        expect(result.verdict).to eq(:unit_test_behavior)
        expect(result.confidence).to eq(:medium)
        expect(result.reasoning).to include('Likely unit test behavior')
        expect(result.reasoning).to include('Some mixed signals present')
      end
    end

    context 'with mixed signals favoring integration test' do
      let(:profile_data) do
        SpecScout::ProfileData.new(
          example_location: 'spec/requests/api/users_spec.rb:25',
          spec_type: :model,
          runtime_ms: 50, # moderate execution
          factories: { user: { strategy: :build_stubbed, count: 1 } }, # minimal factories
          db: { inserts: 5, selects: 8, total_queries: 13 }, # heavy database
          events: {},
          metadata: {}
        )
      end

      it 'identifies likely integration test behavior with medium confidence' do
        agent = described_class.new(profile_data)
        result = agent.evaluate

        expect(result.verdict).to eq(:integration_test_behavior)
        expect(result.confidence).to eq(:medium)
        expect(result.reasoning).to include('Likely integration test behavior')
        expect(result.reasoning).to include('Some mixed signals present')
      end
    end

    context 'with completely mixed signals' do
      let(:profile_data) do
        SpecScout::ProfileData.new(
          example_location: 'spec/other/unknown_spec.rb:10',
          spec_type: :model,
          runtime_ms: 50, # moderate execution
          factories: { user: { strategy: :create, count: 2 } }, # moderate factories
          db: { inserts: 2, selects: 4, total_queries: 6 }, # moderate database
          events: {},
          metadata: {}
        )
      end

      it 'returns unclear intent with low confidence' do
        agent = described_class.new(profile_data)
        result = agent.evaluate

        expect(result.verdict).to eq(:intent_unclear)
        expect(result.confidence).to eq(:low)
        expect(result.reasoning).to include('Mixed behavioral signals detected')
        expect(result.reasoning).to include('Unable to clearly classify test intent')
      end
    end

    describe 'file location pattern matching' do
      context 'with unit test file patterns' do
        %w[
          spec/models/user_spec.rb
          spec/lib/utils_spec.rb
          spec/services/user_service_spec.rb
          spec/helpers/application_helper_spec.rb
          spec/presenters/user_presenter_spec.rb
          spec/decorators/user_decorator_spec.rb
          spec/serializers/user_serializer_spec.rb
          spec/validators/email_validator_spec.rb
          spec/concerns/trackable_spec.rb
          spec/jobs/email_job_spec.rb
        ].each do |location|
          it "recognizes #{location} as unit test location" do
            profile_data = SpecScout::ProfileData.new(
              example_location: "#{location}:42",
              spec_type: :model,
              runtime_ms: runtime_ms,
              factories: factories_data,
              db: db_data,
              events: {},
              metadata: {}
            )
            agent = described_class.new(profile_data)
            result = agent.evaluate

            expect(result.metadata[:file_location_signal]).to eq(:unit_test_location)
          end
        end
      end

      context 'with integration test file patterns' do
        %w[
          spec/features/user_registration_spec.rb
          spec/integration/api_spec.rb
          spec/system/user_flow_spec.rb
          spec/requests/users_spec.rb
          spec/controllers/users_controller_spec.rb
          spec/routing/routes_spec.rb
          spec/views/users/index_spec.rb
          spec/mailers/user_mailer_spec.rb
        ].each do |location|
          it "recognizes #{location} as integration test location" do
            profile_data = SpecScout::ProfileData.new(
              example_location: "#{location}:42",
              spec_type: :model,
              runtime_ms: runtime_ms,
              factories: factories_data,
              db: db_data,
              events: {},
              metadata: {}
            )
            agent = described_class.new(profile_data)
            result = agent.evaluate

            expect(result.metadata[:file_location_signal]).to eq(:integration_test_location)
          end
        end
      end
    end

    describe 'runtime behavior analysis' do
      context 'with fast execution (0-10ms)' do
        let(:profile_data) do
          SpecScout::ProfileData.new(
            example_location: 'spec/models/user_spec.rb:42',
            spec_type: :model,
            runtime_ms: 8,
            factories: factories_data,
            db: db_data,
            events: {},
            metadata: {}
          )
        end

        it 'identifies fast execution pattern' do
          agent = described_class.new(profile_data)
          result = agent.evaluate

          expect(result.metadata[:runtime_behavior_signal]).to eq(:fast_execution)
        end
      end

      context 'with moderate execution (11-100ms)' do
        let(:profile_data) do
          SpecScout::ProfileData.new(
            example_location: 'spec/models/user_spec.rb:42',
            spec_type: :model,
            runtime_ms: 50,
            factories: factories_data,
            db: db_data,
            events: {},
            metadata: {}
          )
        end

        it 'identifies moderate execution pattern' do
          agent = described_class.new(profile_data)
          result = agent.evaluate

          expect(result.metadata[:runtime_behavior_signal]).to eq(:moderate_execution)
        end
      end

      context 'with slow execution (>100ms)' do
        let(:profile_data) do
          SpecScout::ProfileData.new(
            example_location: 'spec/models/user_spec.rb:42',
            spec_type: :model,
            runtime_ms: 150,
            factories: factories_data,
            db: db_data,
            events: {},
            metadata: {}
          )
        end

        it 'identifies slow execution pattern' do
          agent = described_class.new(profile_data)
          result = agent.evaluate

          expect(result.metadata[:runtime_behavior_signal]).to eq(:slow_execution)
        end
      end
    end
  end

  describe '#agent_name' do
    let(:profile_data) do
      SpecScout::ProfileData.new(
        example_location: 'spec/models/user_spec.rb:42',
        spec_type: :model,
        runtime_ms: runtime_ms,
        factories: factories_data,
        db: db_data,
        events: {},
        metadata: {}
      )
    end

    it 'returns :intent' do
      agent = described_class.new(profile_data)
      expect(agent.agent_name).to eq(:intent)
    end
  end
end
