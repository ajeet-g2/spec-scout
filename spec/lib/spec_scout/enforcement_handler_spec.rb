# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SpecScout::EnforcementHandler do
  let(:config) { SpecScout::Configuration.new }
  let(:enforcement_handler) { described_class.new(config) }
  let(:high_confidence_recommendation) do
    SpecScout::Recommendation.new(
      spec_location: 'spec/test_spec.rb:10',
      action: :replace_factory_strategy,
      from_value: 'create(:user)',
      to_value: 'build_stubbed(:user)',
      confidence: :high,
      explanation: ['High confidence optimization'],
      agent_results: []
    )
  end
  let(:medium_confidence_recommendation) do
    SpecScout::Recommendation.new(
      spec_location: 'spec/test_spec.rb:20',
      action: :optimize_database_usage,
      from_value: nil,
      to_value: nil,
      confidence: :medium,
      explanation: ['Medium confidence optimization'],
      agent_results: []
    )
  end

  describe '#initialize' do
    it 'initializes with configuration' do
      expect(enforcement_handler).to be_a(described_class)
    end
  end

  describe '#enforcement_enabled?' do
    it 'returns false by default' do
      expect(enforcement_handler.enforcement_enabled?).to be false
    end

    it 'returns true when enforcement mode is enabled' do
      config.enforcement_mode = true
      expect(enforcement_handler.enforcement_enabled?).to be true
    end
  end

  describe '#should_fail?' do
    context 'when enforcement is disabled' do
      before { config.enforcement_mode = false }

      it 'returns false for any recommendation' do
        expect(enforcement_handler.should_fail?(high_confidence_recommendation)).to be false
      end
    end

    context 'when enforcement is enabled' do
      before do
        config.enforcement_mode = true
        config.fail_on_high_confidence = true
      end

      it 'returns true for high confidence recommendations' do
        expect(enforcement_handler.should_fail?(high_confidence_recommendation)).to be true
      end

      it 'returns false for medium confidence recommendations' do
        expect(enforcement_handler.should_fail?(medium_confidence_recommendation)).to be false
      end

      it 'returns false for nil recommendations' do
        expect(enforcement_handler.should_fail?(nil)).to be false
      end
    end
  end

  describe '#handle_enforcement' do
    context 'when enforcement is disabled' do
      before { config.enforcement_mode = false }

      it 'returns success result' do
        result = enforcement_handler.handle_enforcement(high_confidence_recommendation)

        expect(result[:should_fail]).to be false
        expect(result[:exit_code]).to eq(0)
      end
    end

    context 'when enforcement is enabled' do
      before do
        config.enforcement_mode = true
        config.fail_on_high_confidence = true
      end

      it 'handles high confidence recommendations as failures' do
        result = enforcement_handler.handle_enforcement(high_confidence_recommendation)

        expect(result[:should_fail]).to be true
        expect(result[:exit_code]).to eq(1)
        expect(result[:enforcement_message]).to include('High confidence recommendation requires action')
      end

      it 'handles medium confidence recommendations as success' do
        result = enforcement_handler.handle_enforcement(medium_confidence_recommendation)

        expect(result[:should_fail]).to be false
        expect(result[:exit_code]).to eq(0)
        expect(result[:enforcement_message]).to include('No immediate action required')
      end
    end
  end

  describe '#exit_code_for_recommendation' do
    context 'when enforcement is disabled' do
      before { config.enforcement_mode = false }

      it 'returns 0 for any recommendation' do
        expect(enforcement_handler.exit_code_for_recommendation(high_confidence_recommendation)).to eq(0)
      end
    end

    context 'when enforcement is enabled' do
      before do
        config.enforcement_mode = true
        config.fail_on_high_confidence = true
      end

      it 'returns 1 for high confidence recommendations' do
        expect(enforcement_handler.exit_code_for_recommendation(high_confidence_recommendation)).to eq(1)
      end

      it 'returns 0 for medium confidence recommendations' do
        expect(enforcement_handler.exit_code_for_recommendation(medium_confidence_recommendation)).to eq(0)
      end

      it 'returns 0 for nil recommendations' do
        expect(enforcement_handler.exit_code_for_recommendation(nil)).to eq(0)
      end
    end
  end

  describe '#ci_friendly?' do
    context 'when enforcement is disabled' do
      before { config.enforcement_mode = false }

      it 'returns true' do
        expect(enforcement_handler.ci_friendly?).to be true
      end
    end

    context 'when enforcement is enabled' do
      before { config.enforcement_mode = true }

      it 'returns true when properly configured' do
        config.fail_on_high_confidence = true
        config.output_format = :json

        expect(enforcement_handler.ci_friendly?).to be true
      end

      it 'returns false when not properly configured' do
        config.fail_on_high_confidence = false

        expect(enforcement_handler.ci_friendly?).to be false
      end
    end
  end

  describe '#validate_enforcement_config!' do
    context 'when auto_apply is enabled with enforcement' do
      before do
        config.enforcement_mode = true
        config.auto_apply_enabled = true
      end

      it 'raises an enforcement failure error' do
        expect { enforcement_handler.validate_enforcement_config! }.to raise_error(
          SpecScout::EnforcementHandler::EnforcementFailureError,
          /Enforcement mode with auto-apply is dangerous/
        )
      end
    end

    context 'when properly configured' do
      before do
        config.enforcement_mode = true
        config.auto_apply_enabled = false
      end

      it 'does not raise an error' do
        expect { enforcement_handler.validate_enforcement_config! }.not_to raise_error
      end
    end
  end

  describe '#enforcement_status' do
    it 'returns enforcement status information' do
      status = enforcement_handler.enforcement_status

      expect(status).to include(
        :enabled,
        :fail_on_high_confidence,
        :ci_friendly,
        :auto_apply_disabled,
        :output_format
      )
    end
  end
end
