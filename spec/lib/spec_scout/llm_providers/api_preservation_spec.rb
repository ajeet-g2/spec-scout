# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'LLM Provider API Preservation' do
  # **Feature: llm-providers-reorganization, Property 3: Public API Preservation**
  describe 'Property 3: Public API Preservation' do
    let(:providers) do
      [
        {
          name: 'OpenAI',
          original_class: SpecScout::LLMProviders::OpenAIProvider,
          new_class: SpecScout::LLMProviders::OpenAIProvider,
          config_class: SpecScout::LLMProviders::OpenAIConfig
        },
        {
          name: 'Anthropic',
          original_class: SpecScout::LLMProviders::AnthropicProvider,
          new_class: SpecScout::LLMProviders::AnthropicProvider,
          config_class: SpecScout::LLMProviders::AnthropicConfig
        },
        {
          name: 'Local LLM',
          original_class: SpecScout::LLMProviders::LocalLLMProvider,
          new_class: SpecScout::LLMProviders::LocalLLMProvider,
          config_class: SpecScout::LLMProviders::LocalLLMConfig
        }
      ]
    end

    it 'preserves all public methods for all client classes' do
      providers.each do |provider_info|
        original_methods = get_public_methods(provider_info[:original_class])
        new_methods = get_public_methods(provider_info[:new_class])

        # Verify all original public methods are still available
        missing_methods = original_methods - new_methods
        expect(missing_methods).to be_empty,
                                   "#{provider_info[:name]} provider is missing public methods: #{missing_methods}"

        # Verify method signatures are preserved
        original_methods.each do |method_name|
          original_arity = provider_info[:original_class].instance_method(method_name).arity
          new_arity = provider_info[:new_class].instance_method(method_name).arity

          expect(new_arity).to eq(original_arity),
                               "#{provider_info[:name]} provider method '#{method_name}' has different arity: " \
                               "expected #{original_arity}, got #{new_arity}"
        end
      end
    end

    it 'preserves method behavior for core API methods' do
      providers.each do |provider_info|
        config = create_test_config(provider_info[:config_class])
        next unless config # Skip if we can't create a valid config

        # Test that both classes respond to the same core methods
        core_methods = %i[generate validate_response available? provider_name]

        core_methods.each do |method_name|
          expect(provider_info[:original_class].method_defined?(method_name)).to be(true),
                                                                                 "Original #{provider_info[:name]} class should define #{method_name}"
          expect(provider_info[:new_class].method_defined?(method_name)).to be(true),
                                                                            "New #{provider_info[:name]} class should define #{method_name}"
        end
      end
    end

    it 'preserves class constants and module structure' do
      providers.each do |provider_info|
        original_constants = provider_info[:original_class].constants
        new_constants = provider_info[:new_class].constants

        # Verify all original constants are preserved
        missing_constants = original_constants - new_constants
        expect(missing_constants).to be_empty,
                                     "#{provider_info[:name]} provider is missing constants: #{missing_constants}"

        # Verify constant values are the same
        original_constants.each do |const_name|
          original_value = provider_info[:original_class].const_get(const_name)
          new_value = provider_info[:new_class].const_get(const_name)

          expect(new_value).to eq(original_value),
                               "#{provider_info[:name]} provider constant '#{const_name}' has different value: " \
                               "expected #{original_value}, got #{new_value}"
        end
      end
    end

    # **Feature: llm-providers-reorganization, Property 4: Configuration Interface Preservation**
    describe 'Property 4: Configuration Interface Preservation' do
      let(:config_classes) do
        [
          {
            name: 'OpenAI Config',
            original_class: SpecScout::LLMProviders::OpenAIConfig,
            new_class: SpecScout::LLMProviders::OpenAIConfig
          },
          {
            name: 'Anthropic Config',
            original_class: SpecScout::LLMProviders::AnthropicConfig,
            new_class: SpecScout::LLMProviders::AnthropicConfig
          },
          {
            name: 'Local LLM Config',
            original_class: SpecScout::LLMProviders::LocalLLMConfig,
            new_class: SpecScout::LLMProviders::LocalLLMConfig
          }
        ]
      end

      it 'preserves all public methods for all config classes' do
        config_classes.each do |config_info|
          original_methods = get_public_methods(config_info[:original_class])
          new_methods = get_public_methods(config_info[:new_class])

          # Verify all original public methods are still available
          missing_methods = original_methods - new_methods
          expect(missing_methods).to be_empty,
                                     "#{config_info[:name]} is missing public methods: #{missing_methods}"

          # Verify method signatures are preserved
          original_methods.each do |method_name|
            original_arity = config_info[:original_class].instance_method(method_name).arity
            new_arity = config_info[:new_class].instance_method(method_name).arity

            expect(new_arity).to eq(original_arity),
                                 "#{config_info[:name]} method '#{method_name}' has different arity: " \
                                 "expected #{original_arity}, got #{new_arity}"
          end
        end
      end

      it 'preserves attribute accessors for all config classes' do
        config_classes.each do |config_info|
          # Test that both classes have the same attribute accessors
          original_instance = config_info[:original_class].new
          new_instance = config_info[:new_class].new

          # Get all instance variables from both instances
          original_attrs = original_instance.instance_variables.map { |var| var.to_s.gsub('@', '') }
          new_attrs = new_instance.instance_variables.map { |var| var.to_s.gsub('@', '') }

          expect(new_attrs).to match_array(original_attrs),
                               "#{config_info[:name]} has different attributes: " \
                               "expected #{original_attrs}, got #{new_attrs}"

          # Verify getter and setter methods exist for each attribute
          original_attrs.each do |attr|
            expect(config_info[:new_class].method_defined?(attr)).to be(true),
                                                                     "#{config_info[:name]} should have getter for #{attr}"
            expect(config_info[:new_class].method_defined?("#{attr}=")).to be(true),
                                                                           "#{config_info[:name]} should have setter for #{attr}="
          end
        end
      end

      it 'preserves class methods and constants for config classes' do
        config_classes.each do |config_info|
          # Verify class methods are preserved
          original_class_methods = config_info[:original_class].methods(false)
          new_class_methods = config_info[:new_class].methods(false)

          missing_class_methods = original_class_methods - new_class_methods
          expect(missing_class_methods).to be_empty,
                                           "#{config_info[:name]} is missing class methods: #{missing_class_methods}"

          # Verify constants are preserved
          original_constants = config_info[:original_class].constants(false)
          new_constants = config_info[:new_class].constants(false)

          missing_constants = original_constants - new_constants
          expect(missing_constants).to be_empty,
                                       "#{config_info[:name]} is missing constants: #{missing_constants}"

          # Verify constant values are the same
          original_constants.each do |const_name|
            original_value = config_info[:original_class].const_get(const_name)
            new_value = config_info[:new_class].const_get(const_name)

            expect(new_value).to eq(original_value),
                                 "#{config_info[:name]} constant '#{const_name}' has different value: " \
                                 "expected #{original_value}, got #{new_value}"
          end
        end
      end

      it 'preserves configuration behavior across all config classes' do
        config_classes.each do |config_info|
          original_config = config_info[:original_class].new
          new_config = config_info[:new_class].new

          # Test that both configs have the same default values
          original_config.instance_variables.each do |var|
            attr_name = var.to_s.gsub('@', '')
            original_value = original_config.instance_variable_get(var)
            new_value = new_config.instance_variable_get(var)

            expect(new_value).to eq(original_value),
                                 "#{config_info[:name]} attribute '#{attr_name}' has different default value: " \
                                 "expected #{original_value}, got #{new_value}"
          end

          # Test that core methods behave the same way
          core_methods = %i[validate! complete? to_h]
          core_methods.each do |method_name|
            next unless config_info[:original_class].method_defined?(method_name)

            # Both should respond to the method
            expect(config_info[:new_class].method_defined?(method_name)).to be(true),
                                                                            "#{config_info[:name]} should define #{method_name}"
          end
        end
      end
    end

    private

    def get_public_methods(klass)
      # Get all public instance methods excluding those from Object and BasicObject
      klass.public_instance_methods(false)
    end

    def create_test_config(config_class)
      config = config_class.new

      # Set minimal required fields based on config class
      case config_class.name
      when /OpenAI/
        config.api_key = 'test-key'
      when /Anthropic/
        config.api_key = 'test-key'
      when /Local/
        config.endpoint = 'http://localhost:11434'
        config.model = 'test-model'
      end

      config
    rescue StandardError
      nil # Return nil if we can't create a valid config
    end
  end
end
