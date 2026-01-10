# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SpecScout::ResponseParser do
  let(:parser) { described_class.new }

  describe '#parse' do
    context 'with valid JSON response' do
      let(:valid_response) do
        {
          'verdict' => 'db_unnecessary',
          'confidence' => 'high',
          'reasoning' => 'No database writes detected',
          'metadata' => { 'query_count' => 0 }
        }.to_json
      end

      it 'parses database agent response successfully' do
        result = parser.parse(valid_response, :database)

        expect(result).to be_a(SpecScout::OptimizerResult)
        expect(result.optimizer_name).to eq(:database)
        expect(result.verdict).to eq(:db_unnecessary)
        expect(result.confidence).to eq(:high)
        expect(result.reasoning).to eq('No database writes detected')
        expect(result.metadata).to include('query_count' => 0)
      end

      it 'parses factory agent response successfully' do
        factory_response = {
          'verdict' => 'prefer_build_stubbed',
          'confidence' => 'medium',
          'reasoning' => 'Factory persistence not required',
          'metadata' => { 'factory_count' => 2 }
        }.to_json

        result = parser.parse(factory_response, :factory)

        expect(result.optimizer_name).to eq(:factory)
        expect(result.verdict).to eq(:prefer_build_stubbed)
        expect(result.confidence).to eq(:medium)
        expect(result.reasoning).to eq('Factory persistence not required')
      end

      it 'parses intent agent response successfully' do
        intent_response = {
          'verdict' => 'unit_test_behavior',
          'confidence' => 'high',
          'reasoning' => 'Test exhibits unit test patterns',
          'test_classification' => {
            'primary_type' => 'unit',
            'boundaries_crossed' => []
          }
        }.to_json

        result = parser.parse(intent_response, :intent)

        expect(result.optimizer_name).to eq(:intent)
        expect(result.verdict).to eq(:unit_test_behavior)
        expect(result.metadata).to include(:test_classification)
      end

      it 'parses risk agent response successfully' do
        risk_response = {
          'verdict' => 'potential_side_effects',
          'confidence' => 'medium',
          'reasoning' => 'Callbacks detected',
          'risk_factors' => [
            {
              'type' => 'after_commit_callback',
              'severity' => 'high'
            }
          ],
          'safety_recommendations' => ['Test callbacks separately']
        }.to_json

        result = parser.parse(risk_response, :risk)

        expect(result.optimizer_name).to eq(:risk)
        expect(result.verdict).to eq(:potential_side_effects)
        expect(result.metadata).to include(:risk_factors, :safety_recommendations)
      end
    end

    context 'with additional fields in response' do
      it 'includes recommendations in metadata' do
        response_with_recommendations = {
          'verdict' => 'db_unnecessary',
          'confidence' => 'high',
          'reasoning' => 'Test reasoning',
          'recommendations' => [
            {
              'action' => 'replace_factory_strategy',
              'from' => 'create(:user)',
              'to' => 'build_stubbed(:user)'
            }
          ]
        }.to_json

        result = parser.parse(response_with_recommendations, :database)

        expect(result.metadata).to include(:recommendations)
        expect(result.metadata[:recommendations]).to be_an(Array)
        expect(result.metadata[:recommendations].first).to include('action' => 'replace_factory_strategy')
      end

      it 'includes performance impact in metadata' do
        response_with_performance = {
          'verdict' => 'prefer_build_stubbed',
          'confidence' => 'high',
          'reasoning' => 'Test reasoning',
          'performance_impact' => '60% improvement expected'
        }.to_json

        result = parser.parse(response_with_performance, :factory)

        expect(result.metadata).to include(performance_impact: '60% improvement expected')
      end
    end

    context 'with missing required fields' do
      it 'creates fallback result when verdict is missing' do
        incomplete_response = {
          'confidence' => 'high',
          'reasoning' => 'Test reasoning'
        }.to_json

        result = parser.parse(incomplete_response, :database)

        expect(result.verdict).to eq(:optimizer_failed)
        expect(result.confidence).to eq(:low)
        expect(result.reasoning).to include('Missing required fields: verdict')
        expect(result.metadata).to include(error: true, parser_error: true)
      end

      it 'creates fallback result when confidence is missing' do
        incomplete_response = {
          'verdict' => 'db_unnecessary',
          'reasoning' => 'Test reasoning'
        }.to_json

        result = parser.parse(incomplete_response, :database)

        expect(result.verdict).to eq(:optimizer_failed)
        expect(result.reasoning).to include('Missing required fields: confidence')
      end

      it 'creates fallback result when reasoning is missing' do
        incomplete_response = {
          'verdict' => 'db_unnecessary',
          'confidence' => 'high'
        }.to_json

        result = parser.parse(incomplete_response, :database)

        expect(result.verdict).to eq(:optimizer_failed)
        expect(result.reasoning).to include('Missing required fields: reasoning')
      end
    end

    context 'with invalid field values' do
      it 'creates fallback result for invalid verdict' do
        invalid_verdict_response = {
          'verdict' => 'invalid_verdict',
          'confidence' => 'high',
          'reasoning' => 'Test reasoning'
        }.to_json

        result = parser.parse(invalid_verdict_response, :database)

        expect(result.verdict).to eq(:optimizer_failed)
        expect(result.reasoning).to include("Invalid verdict 'invalid_verdict' for agent type 'database'")
      end

      it 'creates fallback result for invalid confidence' do
        invalid_confidence_response = {
          'verdict' => 'db_unnecessary',
          'confidence' => 'invalid_confidence',
          'reasoning' => 'Test reasoning'
        }.to_json

        result = parser.parse(invalid_confidence_response, :database)

        expect(result.verdict).to eq(:optimizer_failed)
        expect(result.reasoning).to include("Invalid confidence level 'invalid_confidence'")
      end
    end

    context 'with invalid JSON' do
      it 'creates fallback result for malformed JSON' do
        malformed_json = '{ "verdict": "db_unnecessary", "confidence": "high" invalid json }'

        result = parser.parse(malformed_json, :database)

        expect(result.verdict).to eq(:optimizer_failed)
        expect(result.confidence).to eq(:low)
        expect(result.reasoning).to include('Invalid JSON response')
        expect(result.metadata).to include(error: true, parser_error: true)
      end

      it 'creates fallback result for empty response' do
        result = parser.parse('', :database)

        expect(result.verdict).to eq(:optimizer_failed)
        expect(result.reasoning).to include('Missing required fields')
      end

      it 'creates fallback result for nil response' do
        result = parser.parse(nil, :database)

        expect(result.verdict).to eq(:optimizer_failed)
        expect(result.reasoning).to include('Missing required fields')
      end
    end

    context 'with invalid agent type' do
      it 'creates fallback result for unsupported agent type' do
        valid_response = {
          'verdict' => 'some_verdict',
          'confidence' => 'high',
          'reasoning' => 'Test reasoning'
        }.to_json

        result = parser.parse(valid_response, :unsupported_agent)

        expect(result.verdict).to eq(:optimizer_failed)
        expect(result.reasoning).to include('Unsupported agent type: unsupported_agent')
      end
    end

    context 'with non-hash JSON response' do
      it 'creates fallback result for array response' do
        array_response = %w[not a hash].to_json

        result = parser.parse(array_response, :database)

        expect(result.verdict).to eq(:optimizer_failed)
        expect(result.reasoning).to include('Response must be a JSON object, got: Array')
      end

      it 'creates fallback result for string response' do
        string_response = '"just a string"'

        result = parser.parse(string_response, :database)

        expect(result.verdict).to eq(:optimizer_failed)
        expect(result.reasoning).to include('Response must be a JSON object, got: String')
      end
    end

    context 'with minimal valid response' do
      it 'handles response with only required fields' do
        minimal_response = {
          'verdict' => 'db_unclear',
          'confidence' => 'low',
          'reasoning' => 'Insufficient data'
        }.to_json

        result = parser.parse(minimal_response, :database)

        expect(result.optimizer_name).to eq(:database)
        expect(result.verdict).to eq(:db_unclear)
        expect(result.confidence).to eq(:low)
        expect(result.reasoning).to eq('Insufficient data')
        expect(result.metadata).to be_a(Hash)
      end
    end

    context 'with all agent types' do
      it 'validates verdicts correctly for each agent type' do
        # Database agent
        db_response = {
          'verdict' => 'db_required',
          'confidence' => 'high',
          'reasoning' => 'Database writes detected'
        }.to_json

        result = parser.parse(db_response, :database)
        expect(result.verdict).to eq(:db_required)

        # Factory agent
        factory_response = {
          'verdict' => 'create_required',
          'confidence' => 'medium',
          'reasoning' => 'Associations require persistence'
        }.to_json

        result = parser.parse(factory_response, :factory)
        expect(result.verdict).to eq(:create_required)

        # Intent agent
        intent_response = {
          'verdict' => 'integration_test_behavior',
          'confidence' => 'high',
          'reasoning' => 'Multiple system boundaries crossed'
        }.to_json

        result = parser.parse(intent_response, :intent)
        expect(result.verdict).to eq(:integration_test_behavior)

        # Risk agent
        risk_response = {
          'verdict' => 'high_risk',
          'confidence' => 'high',
          'reasoning' => 'Complex callback chains detected'
        }.to_json

        result = parser.parse(risk_response, :risk)
        expect(result.verdict).to eq(:high_risk)
      end
    end
  end

  describe 'error handling' do
    it 'includes timestamp in fallback results' do
      result = parser.parse('invalid json', :database)

      expect(result.metadata[:timestamp]).to be_a(Time)
      expect(result.metadata[:error]).to be true
      expect(result.metadata[:parser_error]).to be true
    end

    it 'handles unexpected exceptions gracefully' do
      # Simulate an unexpected error by stubbing JSON.parse to raise a different error
      allow(JSON).to receive(:parse).and_raise(StandardError, 'Unexpected error')

      result = parser.parse('{"valid": "json"}', :database)

      expect(result.verdict).to eq(:optimizer_failed)
      expect(result.reasoning).to include('Response parsing failed: Unexpected error')
    end
  end
end
