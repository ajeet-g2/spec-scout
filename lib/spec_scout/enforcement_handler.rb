# frozen_string_literal: true

module SpecScout
  # Enforcement mode handler for CI-friendly enforcement configuration
  # Handles high-confidence failure conditions and graceful enforcement
  class EnforcementHandler
    class EnforcementFailureError < StandardError
      attr_reader :recommendation, :confidence_level

      def initialize(message, recommendation = nil, confidence_level = nil)
        super(message)
        @recommendation = recommendation
        @confidence_level = confidence_level
      end
    end

    def initialize(config)
      @config = config
    end

    # Check if enforcement mode is enabled
    def enforcement_enabled?
      @config.enforcement_mode?
    end

    # Determine if a recommendation should cause enforcement failure
    def should_fail?(recommendation)
      return false unless enforcement_enabled?
      return false unless recommendation

      recommendation.confidence
      case @config.fail_on_high_confidence
      when true
      else
        # Default enforcement: fail on high confidence recommendations
      end
      :high
    end

    # Handle enforcement for a recommendation
    def handle_enforcement(recommendation, profile_data = nil)
      return { should_fail: false, exit_code: 0 } unless enforcement_enabled?

      if should_fail?(recommendation)
        handle_enforcement_failure(recommendation, profile_data)
      else
        handle_enforcement_success(recommendation)
      end
    end

    # Generate CI-friendly exit codes
    def exit_code_for_recommendation(recommendation)
      return 0 unless enforcement_enabled?

      case recommendation&.confidence
      when :high
        should_fail?(recommendation) ? 1 : 0
      when :medium
        0  # Medium confidence never fails in enforcement mode
      when :low
        0  # Low confidence never fails in enforcement mode
      else
        0  # Unknown confidence defaults to success
      end
    end

    # Format enforcement message for CI output
    def format_enforcement_message(recommendation, profile_data = nil)
      return nil unless enforcement_enabled? && recommendation

      if should_fail?(recommendation)
        format_failure_message(recommendation, profile_data)
      else
        format_success_message(recommendation)
      end
    end

    # Check if enforcement mode is configured correctly for CI
    def ci_friendly?
      return true unless enforcement_enabled?

      # CI-friendly enforcement should:
      # 1. Only fail on high confidence recommendations
      # 2. Provide clear exit codes
      # 3. Have structured output
      @config.fail_on_high_confidence &&
        (@config.output_format == :json || @config.console_output?)
    end

    # Validate enforcement configuration
    def validate_enforcement_config!
      return unless enforcement_enabled?

      unless ci_friendly?
        warn 'Warning: Enforcement mode may not be CI-friendly. Consider enabling fail_on_high_confidence and structured output.'
      end

      return unless @config.auto_apply_enabled?

      raise EnforcementFailureError,
            'Enforcement mode with auto-apply is dangerous and not recommended for CI environments'
    end

    # Get enforcement status summary
    def enforcement_status
      {
        enabled: enforcement_enabled?,
        fail_on_high_confidence: @config.fail_on_high_confidence,
        ci_friendly: ci_friendly?,
        auto_apply_disabled: !@config.auto_apply_enabled?,
        output_format: @config.output_format
      }
    end

    private

    def handle_enforcement_failure(recommendation, profile_data)
      message = format_failure_message(recommendation, profile_data)

      if @config.console_output?
        puts "\n❌ Enforcement Mode: Action Required"
        puts message
        puts "\nThis recommendation requires immediate attention."
        puts 'Exit code: 1'
      end

      {
        should_fail: true,
        exit_code: 1,
        enforcement_message: message,
        recommendation: recommendation
      }
    end

    def handle_enforcement_success(recommendation)
      message = format_success_message(recommendation)

      if @config.console_output? && recommendation
        puts "\n✅ Enforcement Mode: Recommendation Noted"
        puts message
        puts 'Exit code: 0'
      end

      {
        should_fail: false,
        exit_code: 0,
        enforcement_message: message,
        recommendation: recommendation
      }
    end

    def format_failure_message(recommendation, profile_data)
      lines = []
      lines << 'High confidence recommendation requires action:'
      lines << "  Location: #{recommendation.spec_location}"
      lines << "  Action: #{recommendation.action}"

      if recommendation.from_value && recommendation.to_value
        lines << "  Change: #{recommendation.from_value} → #{recommendation.to_value}"
      end

      lines << "  Confidence: #{recommendation.confidence.to_s.upcase}"
      lines << "  Explanation: #{Array(recommendation.explanation).join('; ')}"

      lines << "  Runtime: #{profile_data.runtime_ms}ms" if profile_data

      lines.join("\n")
    end

    def format_success_message(recommendation)
      return 'No high confidence recommendations found.' unless recommendation

      lines = []
      lines << "Recommendation noted (#{recommendation.confidence} confidence):"
      lines << "  Location: #{recommendation.spec_location}"
      lines << "  Action: #{recommendation.action}"
      lines << '  No immediate action required in enforcement mode.'

      lines.join("\n")
    end
  end
end
