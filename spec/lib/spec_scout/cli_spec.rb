# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SpecScout::CLI do
  describe '.run' do
    context 'with --help flag' do
      it 'prints help and exits' do
        expect { described_class.run(['--help']) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(0)
        end
      end
    end

    context 'with --version flag' do
      it 'prints version and exits' do
        expect { described_class.run(['--version']) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(0)
        end
      end
    end

    context 'with --disable flag' do
      it 'disables SpecScout' do
        expect_any_instance_of(SpecScout::SpecScout).to receive(:analyze).and_return(
          { disabled: true, recommendation: nil, should_fail: false }
        )

        expect { described_class.run(['--disable']) }.not_to raise_error
      end
    end

    context 'with invalid arguments' do
      it 'handles unknown options gracefully' do
        expect { described_class.run(['--unknown-option']) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end

      it 'handles missing argument values' do
        expect { described_class.run(['--output']) }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end
    end
  end

  describe '.parse_args' do
    it 'parses disable flag' do
      config = described_class.send(:parse_args, ['--disable'])
      expect(config.enabled?).to be false
    end

    it 'parses no-testprof flag' do
      config = described_class.send(:parse_args, ['--no-testprof'])
      expect(config.test_prof_enabled?).to be false
    end

    it 'parses enforce flag' do
      config = described_class.send(:parse_args, ['--enforce'])
      expect(config.enforcement_mode?).to be true
    end

    it 'parses output format' do
      config = described_class.send(:parse_args, ['--output', 'json'])
      expect(config.output_format).to eq(:json)
    end

    it 'parses agent enable/disable' do
      config = described_class.send(:parse_args, ['--disable-agent', 'risk'])
      expect(config.agent_enabled?(:risk)).to be false
    end

    it 'validates configuration after parsing' do
      expect { described_class.send(:parse_args, ['--output', 'invalid']) }.to raise_error(ArgumentError)
    end
  end

  describe 'output handling' do
    let(:config) { SpecScout::Configuration.new }

    it 'handles disabled result' do
      result = { disabled: true }
      expect { described_class.send(:handle_output, result, config) }.to output(/disabled/).to_stdout
    end

    it 'handles no profile data result' do
      result = { no_profile_data: true }
      expect { described_class.send(:handle_output, result, config) }.to output(/No profile data/).to_stdout
    end

    it 'handles error result' do
      result = { error: StandardError.new('Test error') }
      expect { described_class.send(:handle_output, result, config) }.to output(/Test error/).to_stdout
    end
  end

  describe 'exit code determination' do
    let(:config) { SpecScout::Configuration.new }

    it 'returns 0 for normal operation' do
      result = { should_fail: false }
      exit_code = described_class.send(:determine_exit_code, result, config)
      expect(exit_code).to eq(0)
    end

    it 'returns 1 for enforcement mode failures' do
      config.enforcement_mode = true
      result = { should_fail: true }
      exit_code = described_class.send(:determine_exit_code, result, config)
      expect(exit_code).to eq(1)
    end

    it 'returns 0 when enforcement mode is disabled' do
      config.enforcement_mode = false
      result = { should_fail: true }
      exit_code = described_class.send(:determine_exit_code, result, config)
      expect(exit_code).to eq(0)
    end
  end
end
