# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SpecScout::TestProfIntegration do
  let(:config) { SpecScout::Configuration.new }
  let(:integration) { described_class.new(config) }

  describe '#initialize' do
    it 'accepts a configuration' do
      expect(integration).to be_a(described_class)
    end

    it 'uses default configuration when none provided' do
      integration = described_class.new
      expect(integration).to be_a(described_class)
    end
  end

  describe '#testprof_available?' do
    it 'returns true when TestProf is available' do
      # TestProf is loaded via gemspec dependency
      expect(integration.testprof_available?).to be true
    end
  end

  describe '#execute_profiling' do
    context 'when TestProf is disabled in config' do
      before { config.use_test_prof = false }

      it 'returns nil without enabling profiling' do
        expect(integration.execute_profiling).to be_nil
      end
    end

    context 'when TestProf is enabled in config' do
      before { config.use_test_prof = true }

      it 'returns profile data when profiling is enabled successfully' do
        result = integration.execute_profiling
        expect(result).to be_a(Hash)
        expect(result).to have_key(:factory_prof)
        expect(result).to have_key(:event_prof)
        expect(result).to have_key(:db_queries)
      end
    end

    context 'when TestProf is not available' do
      before do
        config.use_test_prof = true
        allow(integration).to receive(:testprof_available?).and_return(false)
      end

      it 'raises TestProfError' do
        expect { integration.execute_profiling }.to raise_error(
          SpecScout::TestProfIntegration::TestProfError,
          /TestProf not available/
        )
      end
    end
  end

  describe '#extract_profile_data' do
    context 'when profiling is not enabled' do
      it 'returns empty hash' do
        expect(integration.extract_profile_data).to eq({})
      end
    end

    context 'when profiling is enabled' do
      before do
        config.use_test_prof = true
        integration.execute_profiling
      end

      it 'returns structured profile data' do
        data = integration.extract_profile_data

        expect(data).to be_a(Hash)
        expect(data).to have_key(:factory_prof)
        expect(data).to have_key(:event_prof)
        expect(data).to have_key(:db_queries)
      end

      it 'handles extraction errors gracefully' do
        # Mock an error in factory prof extraction
        allow(integration).to receive(:extract_factory_prof_data).and_raise(StandardError, 'Test error')

        expect { integration.extract_profile_data }.to raise_error(
          SpecScout::TestProfIntegration::TestProfError,
          /Failed to extract TestProf data/
        )
      end
    end
  end
end
