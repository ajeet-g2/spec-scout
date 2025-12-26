# frozen_string_literal: true

# ConsensusEngine aggregates agent verdicts into final recommendations using decision matrix logic.
# It analyzes agent results, identifies risk factors, and determines the best course of action for test optimization.
module SpecScout
  # Aggregates agent verdicts into final recommendations using decision matrix logic
  class ConsensusEngine
    attr_reader :agent_results, :profile_data

    def initialize(agent_results, profile_data)
      @agent_results = Array(agent_results).select(&:valid?)
      @profile_data = profile_data
      validate_inputs!
    end

    # Generate final recommendation based on agent consensus
    def generate_recommendation
      return no_agents_recommendation if agent_results.empty?

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
        agent_results: agent_results
      )
    end

    private

    def validate_inputs!
      raise ArgumentError, 'Profile data must be a ProfileData instance' unless profile_data.is_a?(ProfileData)
      raise ArgumentError, 'Profile data must be valid' unless profile_data.valid?

      agent_results.each do |result|
        next if result.is_a?(AgentResult) && result.valid?

        raise ArgumentError, "Invalid agent result: #{result.inspect}"
      end
    end

    def analyze_consensus
      # Group agents by their verdict types
      verdict_groups = group_by_verdict_category

      # Identify risk factors
      risk_factors = identify_risk_factors

      # Count agreement levels
      agreement_analysis = analyze_agreement_patterns(verdict_groups)

      {
        verdict_groups: verdict_groups,
        risk_factors: risk_factors,
        agreement_analysis: agreement_analysis,
        total_agents: agent_results.size,
        high_confidence_agents: agent_results.count(&:high_confidence?),
        medium_confidence_agents: agent_results.count(&:medium_confidence?),
        low_confidence_agents: agent_results.count(&:low_confidence?)
      }
    end

    def group_by_verdict_category
      optimization_verdicts = []
      risk_verdicts = []
      unclear_verdicts = []

      agent_results.each do |result|
        case result.verdict
        when :db_unnecessary, :prefer_build_stubbed, :strategy_optimal
          optimization_verdicts << result
        when :safe_to_optimize, :potential_side_effects, :high_risk
          risk_verdicts << result
        when :db_unclear, :intent_unclear, :no_verdict
          unclear_verdicts << result
        else
          # Categorize based on confidence and agent type
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

    def identify_risk_factors
      risk_factors = []

      agent_results.each do |result|
        risk_factors.concat(process_verdict_risk(result))
        risk_factors.concat(process_metadata_risk(result))
      end

      risk_factors
    end

    def process_verdict_risk(result)
      case result.verdict
      when :high_risk
        [{ type: :high_risk, agent: result.agent_name, confidence: result.confidence }]
      when :potential_side_effects
        [{ type: :potential_side_effects, agent: result.agent_name, confidence: result.confidence }]
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
      { type: :high_risk_score, agent: result.agent_name, score: result.metadata[:risk_score] }
    end

    def multiple_risk_factors_metadata?(result)
      result.metadata[:total_risk_factors] && result.metadata[:total_risk_factors] > 2
    end

    def multiple_risk_factors_metadata(result)
      { type: :multiple_risk_factors, agent: result.agent_name, count: result.metadata[:total_risk_factors] }
    end

    def analyze_agreement_patterns(verdict_groups)
      optimization_agents = verdict_groups[:optimization]
      risk_agents = verdict_groups[:risk]
      unclear_agents = verdict_groups[:unclear]

      # Count agents agreeing on optimization
      optimization_agreement = count_optimization_agreement(optimization_agents)

      # Check for conflicting signals
      conflicts = detect_conflicts(optimization_agents, risk_agents)

      {
        optimization_agreement: optimization_agreement,
        conflicts: conflicts,
        optimization_count: optimization_agents.size,
        risk_count: risk_agents.size,
        unclear_count: unclear_agents.size,
        strong_optimization_signals: optimization_agents.count do |a|
          a.high_confidence? && optimization_verdict?(a.verdict)
        end,
        strong_risk_signals: risk_agents.count { |a| a.high_confidence? && risk_verdict?(a.verdict) },
        agreement_count: optimization_agreement[:agreement_count] || 0,
        most_common_verdict: optimization_agreement[:most_common_verdict]
      }
    end

    def count_optimization_agreement(optimization_agents)
      verdict_counts = Hash.new(0)

      optimization_agents.each do |agent|
        # Normalize similar verdicts
        normalized_verdict = normalize_verdict(agent.verdict)
        verdict_counts[normalized_verdict] += 1
      end

      # Find the most common optimization verdict
      max_count = verdict_counts.values.max || 0
      most_common_verdict = verdict_counts.key(max_count)

      {
        most_common_verdict: most_common_verdict,
        agreement_count: max_count,
        verdict_distribution: verdict_counts
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

    def detect_conflicts(optimization_agents, risk_agents)
      conflicts = []

      # Conflict: optimization agents suggest changes but risk agents flag dangers
      if optimization_agents.any?(&:high_confidence?) && risk_agents.any? { |a| a.verdict == :high_risk }
        conflicts << {
          type: :optimization_vs_high_risk,
          optimization_agents: optimization_agents.select(&:high_confidence?).map(&:agent_name),
          risk_agents: risk_agents.select { |a| a.verdict == :high_risk }.map(&:agent_name)
        }
      end

      # Conflict: agents disagree on persistence requirements
      db_unnecessary = optimization_agents.select { |a| a.verdict == :db_unnecessary }
      db_required = optimization_agents.select { |a| a.verdict == :db_required }

      if db_unnecessary.any? && db_required.any?
        conflicts << {
          type: :persistence_disagreement,
          unnecessary_agents: db_unnecessary.map(&:agent_name),
          required_agents: db_required.map(&:agent_name)
        }
      end

      conflicts
    end

    def determine_action(consensus_data)
      agreement = consensus_data[:agreement_analysis]
      risk_factors = consensus_data[:risk_factors]

      # High risk scenarios - no action
      return no_action_high_risk(risk_factors) if high_risk_scenario?(risk_factors)

      # Strong agreement scenarios
      return strong_recommendation_action(agreement, risk_factors) if strong_agreement?(agreement)

      # Conflicting agents scenarios
      return soft_suggestion_action(agreement, risk_factors) if conflicting_agents?(agreement)

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

    def conflicting_agents?(agreement)
      agreement[:conflicts].any? ||
        (agreement[:optimization_count] >= 1 && agreement[:risk_count] >= 1)
    end

    def no_action_high_risk(risk_factors)
      high_risk_factors = risk_factors.select { |f| f[:type] == :high_risk }
      risk_agents = high_risk_factors.map { |f| f[:agent] }.join(', ')

      {
        action: :no_action,
        from_value: '',
        to_value: '',
        reason: :high_risk,
        risk_agents: risk_agents
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
      # Generate soft suggestions when agents conflict
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
      # Look for factory-specific recommendations in agent results
      factory_agents = agent_results.select { |r| r.agent_name == :factory }
      return nil if factory_agents.empty?

      factory_agent = factory_agents.first
      return nil unless factory_agent.verdict == :prefer_build_stubbed

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

      # Start with base confidence from agreement strength
      base_confidence = calculate_base_confidence(agreement)

      # Apply risk-based downgrading
      apply_risk_downgrading(base_confidence, risk_factors)
    end

    def calculate_base_confidence(agreement)
      strong_signals = agreement[:strong_optimization_signals] || 0
      agreement_count = agreement[:agreement_count] || 0

      return :high if high_confidence?(strong_signals, agreement_count)
      return :medium if medium_confidence?(strong_signals, agreement_count)

      :low
    end

    def high_confidence?(strong_signals, agreement_count)
      (strong_signals >= 2 && agreement_count >= 3) ||
        (strong_signals >= 2 && agreement_count >= 2)
    end

    def medium_confidence?(strong_signals, agreement_count)
      (strong_signals >= 1 && agreement_count >= 2) ||
        (agreement_count >= 2)
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

      # Add agent summary
      explanation << build_agent_summary(consensus_data)

      # Add consensus analysis
      explanation << build_consensus_analysis(consensus_data)

      # Add action reasoning
      explanation << build_action_reasoning(action_data)

      # Add risk factors if present
      explanation << build_risk_explanation(consensus_data[:risk_factors]) if consensus_data[:risk_factors].any?

      explanation.compact
    end

    def build_agent_summary(consensus_data)
      total = consensus_data[:total_agents]
      high_conf = consensus_data[:high_confidence_agents]
      medium_conf = consensus_data[:medium_confidence_agents]
      low_conf = consensus_data[:low_confidence_agents]

      "Analyzed #{total} agent(s): #{high_conf} high confidence, #{medium_conf} medium confidence, #{low_conf} low confidence"
    end

    def build_consensus_analysis(consensus_data)
      agreement = consensus_data[:agreement_analysis]

      if agreement[:agreement_count] >= 2
        "#{agreement[:agreement_count]} agent(s) agree on #{agreement[:most_common_verdict]} approach"
      elsif agreement[:conflicts].any?
        conflict_types = agreement[:conflicts].map { |c| c[:type] }.join(', ')
        "Conflicting agent opinions detected: #{conflict_types}"
      else
        'No clear consensus among agents'
      end
    end

    def build_action_reasoning(action_data)
      case action_data[:reason]
      when :optimization_agreement
        'Strong agreement supports optimization recommendation'
      when :high_risk
        "High risk factors prevent optimization (flagged by: #{action_data[:risk_agents]})"
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

    def no_agents_recommendation
      Recommendation.new(
        spec_location: profile_data.example_location,
        action: :no_action,
        from_value: '',
        to_value: '',
        confidence: :low,
        explanation: ['No valid agent results available for analysis'],
        agent_results: []
      )
    end

    def optimization_verdict?(verdict)
      %i[db_unnecessary prefer_build_stubbed optimize_persistence].include?(verdict)
    end

    def risk_verdict?(verdict)
      %i[safe_to_optimize potential_side_effects high_risk].include?(verdict)
    end
  end
end
