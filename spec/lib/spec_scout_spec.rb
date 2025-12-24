# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SpecScout do
  describe '.configure' do
    it 'yields configuration block' do
      expect { |b| SpecScout.configure(&b) }.to yield_with_args(SpecScout::Configuration)
    end

    it 'allows configuration changes' do
      SpecScout.configure do |config|
        config.enable = false
        config.output_format = :json
      end

      expect(SpecScout.configuration.enable).to be false
      expect(SpecScout.configuration.output_format).to eq(:json)
    end

    it 'returns configuration' do
      config = SpecScout.configure
      expect(config).to be_a(SpecScout::Configuration)
    end
  end

  describe '.configuration' do
    it 'returns a Configuration instance' do
      expect(SpecScout.configuration).to be_a(SpecScout::Configuration)
    end

    it 'returns the same instance on multiple calls' do
      config1 = SpecScout.configuration
      config2 = SpecScout.configuration
      expect(config1).to be(config2)
    end
  end

  describe '.reset_configuration!' do
    it 'resets configuration to new instance' do
      old_config = SpecScout.configuration
      old_config.enable = false

      SpecScout.reset_configuration!
      new_config = SpecScout.configuration

      expect(new_config).not_to be(old_config)
      expect(new_config.enable).to be true
    end
  end
end
