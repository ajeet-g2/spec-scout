# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Safety and Enforcement Integration' do
  let(:config) { SpecScout::Configuration.new }
  let(:spec_scout) { SpecScout::SpecScout.new(config) }

  describe 'safe mode operation' do
    it 'operates in safe mode by default' do
      expect(spec_scout.safety_validator.safe_mode?).to be true
      expect(spec_scout.enforcement_handler.enforcement_enabled?).to be false
    end

    it 'prevents auto-application by default' do
      expect { spec_scout.safety_validator.prevent_auto_application! }.not_to raise_error
    end

    it 'operates in non-blocking mode by default' do
      expect { spec_scout.safety_validator.validate_non_blocking_mode! }.not_to raise_error
    end
  end

  describe 'enforcement mode with safety' do
    before do
      config.enforcement_mode = true
      config.fail_on_high_confidence = true
    end

    it 'enables enforcement while maintaining safety' do
      expect(spec_scout.enforcement_handler.enforcement_enabled?).to be true
      expect(spec_scout.safety_validator.safe_mode?).to be true
    end

    it 'validates enforcement configuration for safety' do
      expect { spec_scout.enforcement_handler.validate_enforcement_config! }.not_to raise_error
    end

    context 'when auto-apply is enabled with enforcement' do
      before { config.auto_apply_enabled = true }

      it 'raises a safety violation during enforcement validation' do
        expect { spec_scout.enforcement_handler.validate_enforcement_config! }.to raise_error(
          SpecScout::EnforcementHandler::EnforcementFailureError,
          /Enforcement mode with auto-apply is dangerous/
        )
      end
    end
  end

  describe 'CLI safety options' do
    it 'parses safety-related CLI arguments' do
      config = SpecScout::SpecScout.parse_cli_args(['--auto-apply', '--blocking-mode'])

      expect(config.auto_apply_enabled?).to be true
      expect(config.blocking_mode_enabled?).to be true
    end

    it 'maintains safe defaults' do
      config = SpecScout::SpecScout.parse_cli_args([])

      expect(config.auto_apply_enabled?).to be false
      expect(config.blocking_mode_enabled?).to be false
    end
  end

  describe 'safety status reporting' do
    it 'provides comprehensive safety status' do
      safety_status = spec_scout.safety_validator.safety_status
      enforcement_status = spec_scout.enforcement_handler.enforcement_status

      expect(safety_status).to include(
        safe_mode: true,
        auto_apply_disabled: true,
        non_blocking_mode: true
      )

      expect(enforcement_status).to include(
        enabled: false,
        auto_apply_disabled: true,
        ci_friendly: true
      )
    end
  end
end
