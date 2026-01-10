# frozen_string_literal: true

require 'spec_helper'

RSpec.describe SpecScout::LLMProviders::BaseLLMProvider do
  let(:provider) { described_class.new }

  describe '#generate' do
    it 'raises NotImplementedError' do
      expect { provider.generate('template', {}) }.to raise_error(NotImplementedError)
    end
  end

  describe '#validate_response' do
    it 'raises NotImplementedError' do
      expect { provider.validate_response('response') }.to raise_error(NotImplementedError)
    end
  end

  describe '#available?' do
    it 'raises NotImplementedError' do
      expect { provider.available? }.to raise_error(NotImplementedError)
    end
  end

  describe '#provider_name' do
    it 'raises NotImplementedError' do
      expect { provider.provider_name }.to raise_error(NotImplementedError)
    end
  end

  describe '#render_template' do
    it 'substitutes context variables in template' do
      template = 'Hello {{name}}, you are {{age}} years old'
      context = { name: 'Alice', age: 30 }

      result = provider.send(:render_template, template, context)

      expect(result).to eq('Hello Alice, you are 30 years old')
    end

    it 'handles missing variables gracefully' do
      template = 'Hello {{name}}, you are {{age}} years old'
      context = { name: 'Alice' }

      result = provider.send(:render_template, template, context)

      expect(result).to eq('Hello Alice, you are {{age}} years old')
    end

    it 'handles empty context' do
      template = 'Hello {{name}}'
      context = {}

      result = provider.send(:render_template, template, context)

      expect(result).to eq('Hello {{name}}')
    end
  end

  describe '#validate_config' do
    let(:config) { double('config') }

    it 'passes when all required fields are present' do
      allow(config).to receive(:api_key).and_return('test-key')
      allow(config).to receive(:model).and_return('test-model')

      expect { provider.send(:validate_config, config, %i[api_key model]) }.not_to raise_error
    end

    it 'raises error when required field is nil' do
      allow(config).to receive(:api_key).and_return(nil)
      allow(config).to receive(:model).and_return('test-model')

      expect { provider.send(:validate_config, config, %i[api_key model]) }
        .to raise_error(ArgumentError, /Missing required configuration/)
    end

    it 'raises error when required field is empty' do
      allow(config).to receive(:api_key).and_return('')
      allow(config).to receive(:model).and_return('test-model')

      expect { provider.send(:validate_config, config, %i[api_key model]) }
        .to raise_error(ArgumentError, /Missing required configuration/)
    end
  end

  describe '#handle_api_error' do
    it 'handles timeout errors' do
      error = Timeout::Error.new('timeout')
      result = provider.send(:handle_api_error, error)

      expect(result).to include('API request timed out')
    end

    it 'handles HTTP errors' do
      error = Net::HTTPError.new('HTTP error', double)
      result = provider.send(:handle_api_error, error)

      expect(result).to include('HTTP error')
    end

    it 'handles JSON parse errors' do
      error = JSON::ParserError.new('invalid JSON')
      result = provider.send(:handle_api_error, error)

      expect(result).to include('Invalid JSON response')
    end

    it 'handles generic errors' do
      error = StandardError.new('generic error')
      result = provider.send(:handle_api_error, error)

      expect(result).to include('API error: generic error')
    end
  end
end
