# frozen_string_literal: true

require 'spec_helper'
require 'json'
require 'time'

RSpec.describe SpecScout::OutputFormatter do
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

  let(:agent_results) do
    [
      SpecScout::AgentResult.new(
        agent_name: :database,
        verdict: :db_unnecessary,
        confidence: :high,
        reasoning: 'No database writes detected',
        metadata: {}
      ),
      SpecScout::AgentResult.new(
        agent_name: :factory,
        verdict: :prefer_build_stubbed,
        confidence: :medium,
        reasoning: 'Factory can use build_stubbed',
        metadata: {}
      )
    ]
  end

  let(:recommendation) do
    SpecScout::Recommendation.new(
      spec_location: 'spec/models/user_spec.rb:42',
      action: :replace_factory_strategy,
      from_value: 'create(:user)',
      to_value: 'build_stubbed(:user)',
      confidence: :high,
      explanation: ['Strong agreement supports optimization recommendation'],
      agent_results: agent_results
    )
  end

  subject(:formatter) { described_class.new(recommendation, profile_data) }

  describe '#initialize' do
    it 'accepts valid recommendation and profile data' do
      expect { formatter }.not_to raise_error
    end

    it 'raises error for invalid recommendation' do
      expect { described_class.new(nil, profile_data) }.to raise_error(ArgumentError, 'Invalid recommendation provided')
    end

    it 'raises error for invalid profile data' do
      expect { described_class.new(recommendation, nil) }.to raise_error(ArgumentError, 'Invalid profile data provided')
    end
  end

  describe '#format_recommendation' do
    let(:output) { formatter.format_recommendation }

    it 'includes header with confidence symbol' do
      expect(output).to include('✔ Spec Scout Recommendation')
    end

    it 'includes spec location' do
      expect(output).to include('spec/models/user_spec.rb:42')
    end

    it 'includes profiling summary' do
      expect(output).to include('Summary:')
      expect(output).to include('Factory :user used `create`')
      expect(output).to include('DB inserts: 1')
      expect(output).to include('Runtime: 38ms')
      expect(output).to include('Type: model spec')
    end

    it 'includes agent opinions' do
      expect(output).to include('Agent Signals:')
      expect(output).to include('Database Agent: DB unnecessary (✔ HIGH)')
      expect(output).to include('Factory Agent: prefer build_stubbed (⚠ MEDIUM)')
    end

    it 'includes final recommendation' do
      expect(output).to include('Final Recommendation:')
      expect(output).to include('✔ Replace `create(:user)` with `build_stubbed(:user)`')
      expect(output).to include('Confidence: ✔ HIGH')
    end

    it 'includes reasoning' do
      expect(output).to include('Reasoning:')
      expect(output).to include('- Strong agreement supports optimization recommendation')
    end

    context 'with no action recommendation' do
      let(:recommendation) do
        SpecScout::Recommendation.new(
          spec_location: 'spec/models/user_spec.rb:42',
          action: :no_action,
          from_value: '',
          to_value: '',
          confidence: :low,
          explanation: ['No clear optimization signals'],
          agent_results: []
        )
      end

      it 'formats no action appropriately' do
        expect(output).to include('— No optimization recommended')
        expect(output).to include('Confidence: ? LOW')
      end
    end

    context 'with empty agent results' do
      let(:recommendation) do
        SpecScout::Recommendation.new(
          spec_location: 'spec/models/user_spec.rb:42',
          action: :no_action,
          from_value: '',
          to_value: '',
          confidence: :low,
          explanation: [],
          agent_results: []
        )
      end

      it 'handles empty agent results' do
        expect(output).to include('- No agent results available')
      end
    end

    context 'with minimal profile data' do
      let(:profile_data) do
        SpecScout::ProfileData.new(
          example_location: 'spec/models/user_spec.rb:42',
          spec_type: :unknown,
          runtime_ms: 0,
          factories: {},
          db: {},
          events: {},
          metadata: {}
        )
      end

      let(:recommendation) do
        SpecScout::Recommendation.new(
          spec_location: 'spec/models/user_spec.rb:42',
          action: :no_action,
          from_value: '',
          to_value: '',
          confidence: :low,
          explanation: [],
          agent_results: []
        )
      end

      it 'handles minimal data gracefully' do
        expect(output).to include('Summary:')
        expect(output).not_to include('Factory')
        expect(output).not_to include('DB inserts')
        expect(output).not_to include('Runtime')
      end
    end
  end

  describe '#format_json' do
    subject(:json_output) { formatter.format_json }

    it 'produces valid JSON' do
      expect { JSON.parse(json_output) }.not_to raise_error
    end

    it 'includes all recommendation fields and metadata' do
      data = JSON.parse(json_output)

      expect(data.fetch('spec_location')).to eq('spec/models/user_spec.rb:42')
      expect(data.fetch('action')).to eq('replace_factory_strategy')
      expect(data.fetch('from_value')).to eq('create(:user)')
      expect(data.fetch('to_value')).to eq('build_stubbed(:user)')
      expect(data.fetch('confidence')).to eq('high')
      expect(data.fetch('explanation')).to eq(['Strong agreement supports optimization recommendation'])

      agent_results = data.fetch('agent_results')
      expect(agent_results).to be_an(Array)
      expect(agent_results.length).to eq(2)
      expect(agent_results.first.fetch('agent_name')).to eq('database')
      expect(agent_results.first.fetch('verdict')).to eq('db_unnecessary')
      expect(agent_results.first.fetch('confidence')).to eq('high')

      profile = data.fetch('profile_data')
      expect(profile.fetch('example_location')).to eq('spec/models/user_spec.rb:42')
      expect(profile.fetch('spec_type')).to eq('model')
      expect(profile.fetch('runtime_ms')).to eq(38)

      metadata = data.fetch('metadata')
      expect(metadata.fetch('spec_scout_version')).to eq(SpecScout::VERSION)
      expect { Time.iso8601(metadata.fetch('timestamp')) }.not_to raise_error
    end
  end
end
