# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe SpecScout::SafetyValidator do
  let(:config) { SpecScout::Configuration.new }
  let(:safety_validator) { described_class.new(config) }

  describe '#initialize' do
    it 'initializes with configuration' do
      expect(safety_validator).to be_a(described_class)
    end
  end

  describe '#prevent_auto_application!' do
    context 'when auto_apply is disabled' do
      before { config.auto_apply_enabled = false }

      it 'does not raise an error' do
        expect { safety_validator.prevent_auto_application! }.not_to raise_error
      end
    end

    context 'when auto_apply is enabled' do
      before { config.auto_apply_enabled = true }

      it 'raises a safety violation error' do
        expect { safety_validator.prevent_auto_application! }.to raise_error(
          SpecScout::SafetyValidator::SafetyViolationError,
          /Auto-application of code changes is not allowed by default/
        )
      end
    end
  end

  describe '#validate_non_blocking_mode!' do
    context 'when blocking mode is disabled' do
      before { config.blocking_mode_enabled = false }

      it 'does not raise an error' do
        expect { safety_validator.validate_non_blocking_mode! }.not_to raise_error
      end
    end

    context 'when blocking mode is enabled' do
      before { config.blocking_mode_enabled = true }

      it 'raises a safety violation error' do
        expect { safety_validator.validate_non_blocking_mode! }.to raise_error(
          SpecScout::SafetyValidator::SafetyViolationError,
          /Blocking mode is not allowed by default/
        )
      end
    end
  end

  describe '#safe_mode?' do
    it 'returns true when in safe mode' do
      config.auto_apply_enabled = false
      config.blocking_mode_enabled = false

      expect(safety_validator.safe_mode?).to be true
    end

    it 'returns false when auto_apply is enabled' do
      config.auto_apply_enabled = true
      config.blocking_mode_enabled = false

      expect(safety_validator.safe_mode?).to be false
    end

    it 'returns false when blocking mode is enabled' do
      config.auto_apply_enabled = false
      config.blocking_mode_enabled = true

      expect(safety_validator.safe_mode?).to be false
    end
  end

  describe '#monitor_spec_files' do
    let(:temp_file) { Tempfile.new(['test_spec', '.rb']) }

    before do
      temp_file.write("# Test spec file\n")
      temp_file.close
    end

    after do
      temp_file.unlink
    end

    it 'monitors spec files for changes' do
      safety_validator.monitor_spec_files([temp_file.path])

      expect { safety_validator.validate_no_mutations! }.not_to raise_error
    end

    it 'detects file mutations' do
      safety_validator.monitor_spec_files([temp_file.path])

      # Modify the file
      File.write(temp_file.path, "# Modified spec file\n")

      expect { safety_validator.validate_no_mutations! }.to raise_error(
        SpecScout::SafetyValidator::SafetyViolationError,
        /Safety violation detected.*File modified during analysis/m
      )
    end
  end

  describe '#safety_status' do
    it 'returns safety status information' do
      status = safety_validator.safety_status

      expect(status).to include(
        :safe_mode,
        :monitored_files,
        :auto_apply_disabled,
        :non_blocking_mode,
        :mutations_detected
      )
    end
  end
end
