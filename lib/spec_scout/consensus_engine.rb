# frozen_string_literal: true

# ConsensusEngine aggregates optimizer verdicts into final recommendations using decision matrix logic.
# It analyzes optimizer results, identifies risk factors, and determines the best course of action for test optimization.
module SpecScout
  # Aggregates optimizer verdicts into final recommendations using decision matrix logic
  class ConsensusEngine
    attr_reader :optimizer_results, :profile_data

    def initialize(optimizer_results, profile_data)
      @optimizer_results = Array(optimizer_results).select(&:valid?)
      @profile_data = profile_data
      validate_inputs!
    end

    # Generate final recommendation based on optimizer consensus
    def generate_recommendation
      return no_optimizers_recommendation if optimizer_results.empty?

      consensus_data = analyze_consensus
      action_data = determine_action(consensus_data)
      confidence = calculate_final_confidence(consensus_data, action_data)
      explanation = build_explanation(consensus_data, action_data)

      Recommendation.new(
        spec_location: profile_data.example_location,
        action: action_data[:action],
        from_value: action_data[:from_value],
        to_value: action_data[:to_value],
        confidence: confidence,
        explanation: explanation,
        agent_results: optimizer_results,
        metadata: build_recommendation_metadata(consensus_data)
      )
    end

    private

    def validate_inputs!
      raise ArgumentError, 'Profile data must be a ProfileData instance' unless profile_data.is_a?(ProfileData)
      raise ArgumentError, 'Profile data must be valid' unless profile_data.valid?

      optimizer_results.each do |result|
        next if result.is_a?(OptimizerResult) && result.valid?

        raise ArgumentError, "Invalid optimizer result: #{result.inspect}"
      end
    end

    def analyze_consensus
      # Separate AI and rule-based optimizers
      ai_optimizers, rule_based_optimizers = categorize_optimizers_by_type

      # Group optimizers by their verdict types
      verdict_groups = group_by_verdict_category

      # Identify risk factors
      risk_factors = identify_risk_factors

      # Count agreement levels with AI weighting
      agreement_analysis = analyze_agreement_patterns(verdict_groups, ai_optimizers, rule_based_optimizers)

      {
        verdict_groups: verdict_groups,
        risk_factors: risk_factors,
        agreement_analysis: agreement_analysis,
        total_optimizers: optimizer_results.size,
        ai_optimizers: ai_optimizers,
        rule_based_optimizers: rule_based_optimizers,
        ai_optimizer_count: ai_optimizers.size,
        rule_based_optimizer_count: rule_based_optimizers.size,
        high_confidence_optimizers: optimizer_results.count(&:high_confidence?),
        medium_confidence_optimizers: optimizer_results.count(&:medium_confidence?),
        low_confidence_optimizers: optimizer_results.count(&:low_confidence?),
        ai_high_confidence: ai_optimizers.count(&:high_confidence?),
        rule_based_high_confidence: rule_based_optimizers.count(&:high_confidence?)
      }
    end

    def categorize_optimizers_by_type
      ai_optimizers = []
      rule_based_optimizers = []

      optimizer_results.each do |result|
        if ai_optimizer?(result)
          ai_optimizers << result
        else
          rule_based_optimizers << result
        end
      end

      [ai_optimizers, rule_based_optimizers]
    end

    def ai_optimizer?(result)
      return false unless result.metadata.is_a?(Hash)

      # Check if this result came from an AI optimizer
      result.metadata[:execution_mode] == :ai ||
        result.metadata[:ai_optimizer] == true ||
        result.metadata.key?(:llm_provider) ||
        result.metadata.key?(:ai_reasoning)
    end

    def group_by_verdict_category
      optimization_verdicts = []
      risk_verdicts = []
      unclear_verdicts = []

      optimizer_results.each do |result|
        case result.verdict
        when :db_unnecessary, :prefer_build_stubbed, :strategy_optimal
          optimization_verdicts << result
        when :safe_to_optimize, :potential_side_effects, :high_risk
          risk_verdicts << result
        when :db_unclear, :intent_unclear, :no_verdict
          unclear_verdicts << result
        else
          # Categorize based on confidence and optimizer type
          if result.high_confidence? || result.medium_confidence?
            optimization_verdicts << result
          else
            unclear_verdicts << result
          end
        end
      end

      {
        optimization: optimization_verdicts,
        risk: risk_verdicts,
        unclear: unclear_verdicts
      }
    end

    def build_recommendation_metadata(consensus_data)
      metadata = {}

      # Add AI vs rule-based optimizer information
      metadata[:ai_optimizer_count] = consensus_data[:ai_optimizer_count]
      metadata[:rule_based_optimizer_count] = consensus_data[:rule_based_optimizer_count]
      metadata[:total_optimizer_count] = consensus_data[:total_optimizers]

      # Add execution mode information
      metadata[:execution_mode] = if consensus_data[:ai_optimizer_count].positive? && consensus_data[:rule_based_optimizer_count].positive?
                                    :hybrid
                                  elsif consensus_data[:ai_optimizer_count].positive?
                                    :ai_only
                                  else
                                    :rule_based_only
                                  end

      # Add agreement strength information
      agreement = consensus_data[:agreement_analysis]
      metadata[:ai_agreement_strength] = agreement[:ai_agreement_strength] || 0.0
      metadata[:rule_based_agreement_strength] = agreement[:rule_based_agreement_strength] || 0.0
      metadata[:combined_agreement_strength] =
        (metadata[:ai_agreement_strength] * 1.2) + metadata[:rule_based_agreement_strength]

      # Add weighting information
      metadata[:ai_optimization_weight] = agreement[:ai_optimization_weight] || 0.0
      metadata[:rule_based_optimization_weight] = agreement[:rule_based_optimization_weight] || 0.0

      # Add conflict information
      if agreement[:conflicts].any?
        metadata[:conflicts_detected] = true
        metadata[:conflict_types] = agreement[:conflicts].map { |c| c[:type] }
        metadata[:ai_vs_rule_based_conflict] = agreement[:conflicts].any? do |c|
          c[:type].to_s.include?('ai_vs_rule_based')
        end
      else
        metadata[:conflicts_detected] = false
      end

      # Add fallback information if present
      if consensus_data[:ai_optimizers].any? { |a| a.metadata[:fallback] }
        metadata[:ai_fallback_occurred] = true
        metadata[:fallback_optimizer_count] = consensus_data[:ai_optimizers].count { |a| a.metadata[:fallback] }
      end

      metadata
    end

    def no_optimizers_recommendation
      Recommendation.new(
        spec_location: profile_data.example_location,
        action: :no_action,
        from_value: '',
        to_value: '',
        confidence: :low,
        explanation: ['No valid optimizer results available for analysis'],
        agent_results: [],
        metadata: {
          ai_optimizer_count: 0,
          rule_based_optimizer_count: 0,
          total_optimizer_count: 0,
          execution_mode: :none,
          no_optimizers: true
        }
      )
    end

    # Simplified methods for basic functionality - keeping the original logic
    def identify_risk_factors
      risk_factors = []

      optimizer_results.each do |result|
        risk_factors.concat(process_verdict_risk(result))
        risk_factors.concat(process_metadata_risk(result))
      end

      risk_factors
    end

    def process_verdict_risk(result)
      case result.verdict
      when :high_risk
        [{ type: :high_risk, optimizer: result.optimizer_name, confidence: result.confidence }]
      when :potential_side_effects
        [{ type: :potential_side_effects, optimizer: result.optimizer_name, confidence: result.confidence }]
      else
        []
      end
    end

    def process_metadata_risk(result)
      return [] unless result.metadata.is_a?(Hash)

      risks = []
      risks << high_risk_score_metadata(result) if high_risk_score_metadata?(result)
      risks << multiple_risk_factors_metadata(result) if multiple_risk_factors_metadata?(result)
      risks.compact
    end

    def high_risk_score_metadata?(result)
      result.metadata[:risk_score] && result.metadata[:risk_score] > 4
    end

    def high_risk_score_metadata(result)
      { type: :high_risk_score, optimizer: result.optimizer_name, score: result.metadata[:risk_score] }
    end

    def multiple_risk_factors_metadata?(result)
      result.metadata[:total_risk_factors] && result.metadata[:total_risk_factors] > 2
    end

    def multiple_risk_factors_metadata(result)
      { type: :multiple_risk_factors, optimizer: result.optimizer_name, count: result.metadata[:total_risk_factors] }
    end

    def analyze_agreement_patterns(verdict_groups, ai_optimizers, rule_based_optimizers)
      optimization_optimizers = verdict_groups[:optimization]
      risk_optimizers = verdict_groups[:risk]
      unclear_optimizers = verdict_groups[:unclear]

      # Count optimizers agreeing on optimization with AI weighting
      optimization_agreement = count_optimization_agreement_with_weighting(optimization_optimizers, ai_optimizers)

      # Check for conflicting signals
      conflicts = detect_conflicts(optimization_optimizers, risk_optimizers, ai_optimizers, rule_based_optimizers)

      # Calculate weighted agreement scores
      ai_optimization_weight = calculate_ai_optimization_weight(optimization_optimizers, ai_optimizers)
      rule_based_optimization_weight = calculate_rule_based_optimization_weight(optimization_optimizers,
                                                                                rule_based_optimizers)

      {
        optimization_agreement: optimization_agreement,
        conflicts: conflicts,
        optimization_count: optimization_optimizers.size,
        risk_count: risk_optimizers.size,
        unclear_count: unclear_optimizers.size,
        strong_optimization_signals: optimization_optimizers.count do |a|
          a.high_confidence? && optimization_verdict?(a.verdict)
        end,
        strong_risk_signals: risk_optimizers.count { |a| a.high_confidence? && risk_verdict?(a.verdict) },
        agreement_count: optimization_agreement[:agreement_count] || 0,
        most_common_verdict: optimization_agreement[:most_common_verdict],
        ai_optimization_weight: ai_optimization_weight,
        rule_based_optimization_weight: rule_based_optimization_weight,
        ai_agreement_strength: calculate_ai_agreement_strength(optimization_optimizers, ai_optimizers),
        rule_based_agreement_strength: calculate_rule_based_agreement_strength(optimization_optimizers,
                                                                               rule_based_optimizers)
      }
    end

    def count_optimization_agreement_with_weighting(optimization_optimizers, _ai_optimizers)
      verdict_counts = Hash.new(0)
      weighted_verdict_counts = Hash.new(0.0)

      optimization_optimizers.each do |optimizer|
        # Normalize similar verdicts
        normalized_verdict = normalize_verdict(optimizer.verdict)
        verdict_counts[normalized_verdict] += 1

        # Apply AI weighting (AI optimizers get higher weight)
        weight = ai_optimizer?(optimizer) ? 1.5 : 1.0

        # Apply confidence weighting
        confidence_multiplier = case optimizer.confidence
                                when :high then 1.0
                                when :medium then 0.8
                                when :low then 0.6
                                else 0.3
                                end

        weighted_verdict_counts[normalized_verdict] += weight * confidence_multiplier
      end

      # Find the most common optimization verdict (by count and by weight)
      max_count = verdict_counts.values.max || 0
      most_common_verdict = verdict_counts.key(max_count)

      max_weighted_score = weighted_verdict_counts.values.max || 0.0
      most_weighted_verdict = weighted_verdict_counts.key(max_weighted_score)

      {
        most_common_verdict: most_common_verdict,
        most_weighted_verdict: most_weighted_verdict,
        agreement_count: max_count,
        weighted_agreement_score: max_weighted_score,
        verdict_distribution: verdict_counts,
        weighted_verdict_distribution: weighted_verdict_counts
      }
    end

    def normalize_verdict(verdict)
      case verdict
      when :db_unnecessary, :prefer_build_stubbed
        :optimize_persistence
      when :db_required, :create_required
        :require_persistence
      when :unit_test_behavior
        :unit_test
      when :integration_test_behavior
        :integration_test
      else
        verdict
      end
    end

    def calculate_ai_optimization_weight(optimization_optimizers, _ai_optimizers)
      ai_optimization_optimizers = optimization_optimizers.select { |optimizer| ai_optimizer?(optimizer) }
      return 0.0 if ai_optimization_optimizers.empty?

      total_weight = ai_optimization_optimizers.sum do |optimizer|
        confidence_weight = case optimizer.confidence
                            when :high then 1.0
                            when :medium then 0.8
                            when :low then 0.6
                            else 0.3
                            end
        confidence_weight
      end

      total_weight / ai_optimization_optimizers.size.to_f
    end

    def calculate_rule_based_optimization_weight(optimization_optimizers, _rule_based_optimizers)
      rule_based_optimization_optimizers = optimization_optimizers.reject { |optimizer| ai_optimizer?(optimizer) }
      return 0.0 if rule_based_optimization_optimizers.empty?

      total_weight = rule_based_optimization_optimizers.sum do |optimizer|
        confidence_weight = case optimizer.confidence
                            when :high then 1.0
                            when :medium then 0.8
                            when :low then 0.6
                            else 0.3
                            end
        confidence_weight
      end

      total_weight / rule_based_optimization_optimizers.size.to_f
    end

    def calculate_ai_agreement_strength(optimization_optimizers, _ai_optimizers)
      ai_optimization_optimizers = optimization_optimizers.select { |optimizer| ai_optimizer?(optimizer) }
      return 0.0 if ai_optimization_optimizers.empty?

      # Calculate agreement strength based on verdict consensus and confidence
      verdict_groups = ai_optimization_optimizers.group_by { |optimizer| normalize_verdict(optimizer.verdict) }
      largest_group = verdict_groups.values.max_by(&:size) || []

      return 0.0 if largest_group.empty?

      # Agreement strength = (size of largest group / total AI optimizers) * average confidence
      group_ratio = largest_group.size.to_f / ai_optimization_optimizers.size
      avg_confidence = largest_group.sum do |optimizer|
        case optimizer.confidence
        when :high then 1.0
        when :medium then 0.8
        when :low then 0.6
        else 0.3
        end
      end / largest_group.size.to_f

      group_ratio * avg_confidence
    end

    def calculate_rule_based_agreement_strength(optimization_optimizers, _rule_based_optimizers)
      rule_based_optimization_optimizers = optimization_optimizers.reject { |optimizer| ai_optimizer?(optimizer) }
      return 0.0 if rule_based_optimization_optimizers.empty?

      # Calculate agreement strength based on verdict consensus and confidence
      verdict_groups = rule_based_optimization_optimizers.group_by { |optimizer| normalize_verdict(optimizer.verdict) }
      largest_group = verdict_groups.values.max_by(&:size) || []

      return 0.0 if largest_group.empty?

      # Agreement strength = (size of largest group / total rule-based optimizers) * average confidence
      group_ratio = largest_group.size.to_f / rule_based_optimization_optimizers.size
      avg_confidence = largest_group.sum do |optimizer|
        case optimizer.confidence
        when :high then 1.0
        when :medium then 0.8
        when :low then 0.6
        else 0.3
        end
      end / largest_group.size.to_f

      group_ratio * avg_confidence
    end

    def detect_conflicts(optimization_optimizers, risk_optimizers, ai_optimizers, rule_based_optimizers)
      conflicts = []

      # Conflict: optimization optimizers suggest changes but risk optimizers flag dangers
      if optimization_optimizers.any?(&:high_confidence?) && risk_optimizers.any? { |a| a.verdict == :high_risk }
        conflicts << {
          type: :optimization_vs_high_risk,
          optimization_optimizers: optimization_optimizers.select(&:high_confidence?).map(&:optimizer_name),
          risk_optimizers: risk_optimizers.select { |a| a.verdict == :high_risk }.map(&:optimizer_name)
        }
      end

      # Conflict: optimizers disagree on persistence requirements
      db_unnecessary = optimization_optimizers.select { |a| a.verdict == :db_unnecessary }
      db_required = optimization_optimizers.select { |a| a.verdict == :db_required }

      if db_unnecessary.any? && db_required.any?
        conflicts << {
          type: :persistence_disagreement,
          unnecessary_optimizers: db_unnecessary.map(&:optimizer_name),
          required_optimizers: db_required.map(&:optimizer_name)
        }
      end

      # New conflict: AI optimizers vs rule-based optimizers disagree
      ai_optimization_optimizers = optimization_optimizers.select { |a| ai_optimizer?(a) }
      rule_based_optimization_optimizers = optimization_optimizers.reject { |a| ai_optimizer?(a) }

      if ai_optimization_optimizers.any? && rule_based_optimization_optimizers.any?
        ai_verdicts = ai_optimization_optimizers.map { |a| normalize_verdict(a.verdict) }.uniq
        rule_based_verdicts = rule_based_optimization_optimizers.map { |a| normalize_verdict(a.verdict) }.uniq

        # Check if AI and rule-based optimizers have different primary verdicts
        if (ai_verdicts & rule_based_verdicts).empty?
          conflicts << {
            type: :ai_vs_rule_based_disagreement,
            ai_optimizers: ai_optimization_optimizers.map(&:optimizer_name),
            rule_based_optimizers: rule_based_optimization_optimizers.map(&:optimizer_name),
            ai_verdicts: ai_verdicts,
            rule_based_verdicts: rule_based_verdicts
          }
        end
      end

      # Conflict: High confidence AI optimizer vs high confidence rule-based optimizer
      high_conf_ai = ai_optimizers.select(&:high_confidence?)
      high_conf_rule_based = rule_based_optimizers.select(&:high_confidence?)

      if high_conf_ai.any? && high_conf_rule_based.any?
        ai_verdicts = high_conf_ai.map { |a| normalize_verdict(a.verdict) }.uniq
        rule_based_verdicts = high_conf_rule_based.map { |a| normalize_verdict(a.verdict) }.uniq

        if (ai_verdicts & rule_based_verdicts).empty?
          conflicts << {
            type: :high_confidence_ai_vs_rule_based,
            ai_optimizers: high_conf_ai.map(&:optimizer_name),
            rule_based_optimizers: high_conf_rule_based.map(&:optimizer_name),
            ai_verdicts: ai_verdicts,
            rule_based_verdicts: rule_based_verdicts
          }
        end
      end

      conflicts
    end

    # Simplified action determination - keeping core logic
    def determine_action(consensus_data)
      agreement = consensus_data[:agreement_analysis]
      risk_factors = consensus_data[:risk_factors]

      # High risk scenarios - no action
      return no_action_high_risk(risk_factors) if high_risk_scenario?(risk_factors)

      # Strong agreement scenarios
      return strong_recommendation_action(agreement, risk_factors) if strong_agreement?(agreement)

      # Conflicting optimizers scenarios
      return soft_suggestion_action(agreement, risk_factors) if conflicting_optimizers?(agreement)

      # Unclear signals scenarios
      no_action_unclear_signals(consensus_data)
    end

    def high_risk_scenario?(risk_factors)
      risk_factors.any? { |factor| factor[:type] == :high_risk } ||
        risk_factors.count { |factor| factor[:type] == :potential_side_effects } >= 2
    end

    def strong_agreement?(agreement)
      agreement[:agreement_count] >= 2 && agreement[:strong_optimization_signals] >= 1
    end

    def conflicting_optimizers?(agreement)
      agreement[:conflicts].any? ||
        (agreement[:optimization_count] >= 1 && agreement[:risk_count] >= 1)
    end

    def no_action_high_risk(risk_factors)
      high_risk_factors = risk_factors.select { |f| f[:type] == :high_risk }
      risk_optimizers = high_risk_factors.map { |f| f[:optimizer] }.join(', ')

      {
        action: :no_action,
        from_value: '',
        to_value: '',
        reason: :high_risk,
        risk_optimizers: risk_optimizers
      }
    end

    def strong_recommendation_action(agreement, risk_factors)
      most_common = agreement[:most_common_verdict]

      case most_common
      when :optimize_persistence
        factory_optimization_action(risk_factors)
      when :require_persistence
        maintain_persistence_action
      else
        review_action(most_common)
      end
    end

    def factory_optimization_action(risk_factors)
      # Check if we have specific factory data to make concrete recommendations
      factory_data = extract_factory_data

      if factory_data && risk_factors.none?
        {
          action: :replace_factory_strategy,
          from_value: factory_data[:from_value],
          to_value: factory_data[:to_value],
          reason: :optimization_agreement
        }
      else
        {
          action: :avoid_db_persistence,
          from_value: 'create strategy',
          to_value: 'build_stubbed strategy',
          reason: :optimization_agreement
        }
      end
    end

    def maintain_persistence_action
      {
        action: :no_action,
        from_value: '',
        to_value: '',
        reason: :persistence_required
      }
    end

    def review_action(verdict)
      {
        action: :review_test_intent,
        from_value: '',
        to_value: '',
        reason: :review_needed,
        verdict: verdict
      }
    end

    def soft_suggestion_action(agreement, _risk_factors)
      # Generate soft suggestions when optimizers conflict
      if agreement[:conflicts].any? { |c| c[:type] == :optimization_vs_high_risk }
        {
          action: :assess_risk_factors,
          from_value: '',
          to_value: '',
          reason: :conflicting_risk_assessment
        }
      elsif agreement[:conflicts].any? { |c| c[:type] == :persistence_disagreement }
        {
          action: :review_test_intent,
          from_value: '',
          to_value: '',
          reason: :conflicting_persistence_needs
        }
      else
        {
          action: :no_action,
          from_value: '',
          to_value: '',
          reason: :conflicting_signals
        }
      end
    end

    def no_action_unclear_signals(consensus_data)
      {
        action: :no_action,
        from_value: '',
        to_value: '',
        reason: :unclear_signals,
        unclear_count: consensus_data[:agreement_analysis][:unclear_count]
      }
    end

    def extract_factory_data
      # Look for factory-specific recommendations in optimizer results
      factory_optimizers = optimizer_results.select { |r| r.optimizer_name == :factory }
      return nil if factory_optimizers.empty?

      factory_optimizer = factory_optimizers.first
      return nil unless factory_optimizer.verdict == :prefer_build_stubbed

      # Extract factory information from profile data
      return nil unless profile_data.factories.is_a?(Hash) && profile_data.factories.any?

      factory_name, factory_info = profile_data.factories.first
      return nil unless factory_info.is_a?(Hash) && factory_info[:strategy] == :create

      {
        from_value: "create(:#{factory_name})",
        to_value: "build_stubbed(:#{factory_name})"
      }
    end

    def calculate_final_confidence(consensus_data, action_data)
      return :low if action_data[:action] == :no_action

      agreement = consensus_data[:agreement_analysis]
      risk_factors = consensus_data[:risk_factors]

      # Start with base confidence from agreement strength with AI weighting
      base_confidence = calculate_base_confidence_with_ai_weighting(agreement, consensus_data)

      # Apply risk-based downgrading
      apply_risk_downgrading(base_confidence, risk_factors)
    end

    def calculate_base_confidence_with_ai_weighting(agreement, _consensus_data)
      strong_signals = agreement[:strong_optimization_signals] || 0
      agreement_count = agreement[:agreement_count] || 0

      # Consider AI weighting in confidence calculation
      ai_weight = agreement[:ai_optimization_weight] || 0.0
      rule_based_weight = agreement[:rule_based_optimization_weight] || 0.0
      ai_agreement_strength = agreement[:ai_agreement_strength] || 0.0
      rule_based_agreement_strength = agreement[:rule_based_agreement_strength] || 0.0

      # AI agents get bonus confidence if they agree strongly
      ai_confidence_bonus = ai_agreement_strength > 0.8 ? 1 : 0

      # Combined agreement strength
      combined_strength = (ai_agreement_strength * 1.2) + rule_based_agreement_strength

      return :high if high_confidence_with_ai?(strong_signals, agreement_count, combined_strength, ai_confidence_bonus)
      return :medium if medium_confidence_with_ai?(strong_signals, agreement_count, combined_strength, ai_weight,
                                                   rule_based_weight)

      :low
    end

    def high_confidence_with_ai?(strong_signals, agreement_count, combined_strength, ai_confidence_bonus)
      # Traditional high confidence conditions
      traditional_high = (strong_signals >= 2 && agreement_count >= 3) ||
                         (strong_signals >= 2 && agreement_count >= 2)

      # AI-enhanced high confidence conditions
      ai_enhanced_high = combined_strength >= 1.0 && ai_confidence_bonus.positive?

      # Strong combined agreement
      strong_combined = combined_strength >= 1.2 && agreement_count >= 2

      traditional_high || ai_enhanced_high || strong_combined
    end

    def medium_confidence_with_ai?(strong_signals, agreement_count, combined_strength, ai_weight, rule_based_weight)
      # Traditional medium confidence conditions
      traditional_medium = (strong_signals >= 1 && agreement_count >= 2) ||
                           (agreement_count >= 2)

      # AI-enhanced medium confidence conditions
      ai_enhanced_medium = combined_strength >= 0.6 && (ai_weight > 0.5 || rule_based_weight > 0.5)

      # Moderate combined agreement
      moderate_combined = combined_strength >= 0.8 && agreement_count >= 1

      traditional_medium || ai_enhanced_medium || moderate_combined
    end

    def apply_risk_downgrading(base_confidence, risk_factors)
      return base_confidence if risk_factors.empty?

      # High risk factors force low confidence
      return :low if risk_factors.any? { |f| f[:type] == :high_risk }

      # Multiple potential side effects downgrade confidence
      potential_side_effects = risk_factors.count { |f| f[:type] == :potential_side_effects }
      if potential_side_effects >= 2
        return base_confidence == :high ? :medium : :low
      elsif potential_side_effects >= 1
        return base_confidence == :high ? :medium : base_confidence
      end

      base_confidence
    end

    def build_explanation(consensus_data, action_data)
      explanation = []

      # Add optimizer summary with AI/rule-based breakdown
      explanation << build_optimizer_summary_with_ai_breakdown(consensus_data)

      # Add consensus analysis with AI weighting
      explanation << build_consensus_analysis_with_ai_weighting(consensus_data)

      # Add action reasoning
      explanation << build_action_reasoning(action_data)

      # Add AI-specific explanations
      explanation << build_ai_specific_explanation(consensus_data) if consensus_data[:ai_optimizer_count].positive?

      # Add risk factors if present
      explanation << build_risk_explanation(consensus_data[:risk_factors]) if consensus_data[:risk_factors].any?

      # Add conflict explanations
      if consensus_data[:agreement_analysis][:conflicts].any?
        explanation << build_conflict_explanation(consensus_data[:agreement_analysis][:conflicts])
      end

      explanation.compact
    end

    def build_optimizer_summary_with_ai_breakdown(consensus_data)
      total = consensus_data[:total_optimizers]
      ai_count = consensus_data[:ai_optimizer_count]
      rule_based_count = consensus_data[:rule_based_optimizer_count]
      high_conf = consensus_data[:high_confidence_optimizers]
      medium_conf = consensus_data[:medium_confidence_optimizers]
      low_conf = consensus_data[:low_confidence_optimizers]

      summary = "Analyzed #{total} optimizer(s): #{high_conf} high confidence, #{medium_conf} medium confidence, #{low_conf} low confidence"

      summary += if ai_count.positive? && rule_based_count.positive?
                   " (#{ai_count} AI, #{rule_based_count} rule-based)"
                 elsif ai_count.positive?
                   " (#{ai_count} AI optimizers)"
                 else
                   " (#{rule_based_count} rule-based optimizers)"
                 end

      summary
    end

    def build_consensus_analysis_with_ai_weighting(consensus_data)
      agreement = consensus_data[:agreement_analysis]

      if agreement[:agreement_count] >= 2
        base_analysis = "#{agreement[:agreement_count]} optimizer(s) agree on #{agreement[:most_common_verdict]} approach"

        # Add AI weighting information if relevant
        if consensus_data[:ai_optimizer_count].positive?
          ai_strength = agreement[:ai_agreement_strength] || 0.0
          rule_based_strength = agreement[:rule_based_agreement_strength] || 0.0

          base_analysis += if ai_strength > rule_based_strength
                             ' (AI optimizers show stronger agreement)'
                           elsif rule_based_strength > ai_strength
                             ' (rule-based optimizers show stronger agreement)'
                           else
                             ' (balanced AI and rule-based agreement)'
                           end
        end

        base_analysis
      elsif agreement[:conflicts].any?
        conflict_types = agreement[:conflicts].map { |c| humanize_conflict_type(c[:type]) }.join(', ')
        "Conflicting optimizer opinions detected: #{conflict_types}"
      else
        'No clear consensus among optimizers'
      end
    end

    def build_ai_specific_explanation(consensus_data)
      return nil if consensus_data[:ai_optimizer_count].zero?

      ai_optimizers = consensus_data[:ai_optimizers]
      explanations = []

      # Add AI reasoning if available
      ai_reasoning = ai_optimizers.map { |a| a.metadata[:ai_reasoning] }.compact
      if ai_reasoning.any?
        explanations << "AI analysis: #{ai_reasoning.first}" # Use first AI reasoning as example
      end

      # Add fallback information
      fallback_count = ai_optimizers.count { |a| a.metadata[:fallback] }
      explanations << "#{fallback_count} AI optimizer(s) fell back to rule-based analysis" if fallback_count.positive?

      # Add LLM provider information
      llm_providers = ai_optimizers.map { |a| a.metadata[:llm_provider] }.compact.uniq
      explanations << "LLM provider(s): #{llm_providers.join(', ')}" if llm_providers.any?

      explanations.empty? ? nil : explanations.join('; ')
    end

    def build_conflict_explanation(conflicts)
      return nil if conflicts.empty?

      conflict_explanations = conflicts.map do |conflict|
        case conflict[:type]
        when :ai_vs_rule_based_disagreement
          "AI optimizers (#{conflict[:ai_verdicts].join(', ')}) disagree with rule-based optimizers (#{conflict[:rule_based_verdicts].join(', ')})"
        when :high_confidence_ai_vs_rule_based
          'High-confidence AI and rule-based optimizers have conflicting recommendations'
        else
          humanize_conflict_type(conflict[:type])
        end
      end

      "Conflicts detected: #{conflict_explanations.join('; ')}"
    end

    def humanize_conflict_type(conflict_type)
      case conflict_type
      when :optimization_vs_high_risk
        'optimization vs high risk'
      when :persistence_disagreement
        'persistence requirement disagreement'
      when :ai_vs_rule_based_disagreement
        'AI vs rule-based disagreement'
      when :high_confidence_ai_vs_rule_based
        'high-confidence AI vs rule-based conflict'
      else
        conflict_type.to_s.gsub('_', ' ')
      end
    end

    def build_action_reasoning(action_data)
      case action_data[:reason]
      when :optimization_agreement
        'Strong agreement supports optimization recommendation'
      when :high_risk
        "High risk factors prevent optimization (flagged by: #{action_data[:risk_optimizers]})"
      when :conflicting_risk_assessment
        'Risk assessment conflicts with optimization signals - manual review recommended'
      when :conflicting_persistence_needs
        'Agents disagree on persistence requirements - review test intent'
      when :conflicting_signals
        'Mixed signals from agents - no clear action'
      when :unclear_signals
        "Insufficient clear signals for recommendation (#{action_data[:unclear_count]} unclear)"
      when :persistence_required
        'Analysis indicates database persistence is necessary'
      when :review_needed
        "Test intent review recommended based on #{action_data[:verdict]} signals"
      else
        'Action determined based on agent consensus'
      end
    end

    def build_risk_explanation(risk_factors)
      return nil if risk_factors.empty?

      risk_summary = risk_factors.group_by { |f| f[:type] }
                                 .map { |type, factors| "#{factors.size} #{humanize_symbol(type)}" }
                                 .join(', ')

      "Risk factors detected: #{risk_summary}"
    end

    def humanize_symbol(symbol)
      symbol.to_s.gsub('_', ' ').split.map(&:capitalize).join(' ')
    end

    def optimization_verdict?(verdict)
      %i[db_unnecessary prefer_build_stubbed optimize_persistence].include?(verdict)
    end

    def risk_verdict?(verdict)
      %i[safe_to_optimize potential_side_effects high_risk].include?(verdict)
    end
  end
end
