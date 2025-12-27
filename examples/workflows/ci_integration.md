# CI Integration Workflow

This document provides guidance for integrating SpecScout into your Continuous Integration pipeline.

## Overview

SpecScout can be integrated into CI to:
- Automatically identify optimization opportunities
- Enforce performance standards
- Generate reports for code review
- Track test performance over time

## GitHub Actions Integration

### Basic Analysis

```yaml
name: SpecScout Analysis

on: [push, pull_request]

jobs:
  spec_scout:
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
        
      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.1
          bundler-cache: true
          
      - name: Setup database
        run: |
          bundle exec rails db:create
          bundle exec rails db:migrate
          
      - name: Run SpecScout Analysis
        run: |
          bundle exec spec_scout --output json > spec_scout_results.json
          
      - name: Upload SpecScout Results
        uses: actions/upload-artifact@v3
        with:
          name: spec-scout-results
          path: spec_scout_results.json
```

### Enforcement Mode

```yaml
name: SpecScout Enforcement

on: [push, pull_request]

jobs:
  spec_scout_enforcement:
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
        
      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.1
          bundler-cache: true
          
      - name: Setup database
        run: |
          bundle exec rails db:create
          bundle exec rails db:migrate
          
      - name: Run SpecScout with Enforcement
        run: |
          bundle exec spec_scout --enforce --fail-on-high-confidence --output json
        continue-on-error: true
        id: spec_scout
        
      - name: Process Results
        if: always()
        run: |
          if [ ${{ steps.spec_scout.outcome }} == 'failure' ]; then
            echo "High confidence optimizations found!"
            echo "Review SpecScout recommendations before merging."
            exit 1
          else
            echo "No high confidence optimizations found."
          fi
```

### Performance Tracking

```yaml
name: Performance Tracking

on: [push, pull_request]

jobs:
  performance_tracking:
    runs-on: ubuntu-latest
    
    steps:
      - name: Checkout code
        uses: actions/checkout@v3
        
      - name: Setup Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.1
          bundler-cache: true
          
      - name: Setup database
        run: |
          bundle exec rails db:create
          bundle exec rails db:migrate
          
      - name: Run Tests with Profiling
        run: |
          bundle exec rspec --profile > test_profile.txt
          
      - name: Run SpecScout Analysis
        run: |
          bundle exec spec_scout --output json > spec_scout_results.json
          
      - name: Generate Performance Report
        run: |
          echo "## SpecScout Performance Analysis" >> $GITHUB_STEP_SUMMARY
          echo "" >> $GITHUB_STEP_SUMMARY
          
          # Extract high confidence recommendations
          HIGH_CONFIDENCE=$(jq -r 'select(.confidence == "high") | .spec_location' spec_scout_results.json)
          
          if [ -n "$HIGH_CONFIDENCE" ]; then
            echo "### High Confidence Optimizations Available:" >> $GITHUB_STEP_SUMMARY
            echo "$HIGH_CONFIDENCE" >> $GITHUB_STEP_SUMMARY
          else
            echo "### No high confidence optimizations found" >> $GITHUB_STEP_SUMMARY
          fi
          
      - name: Upload Results
        uses: actions/upload-artifact@v3
        with:
          name: performance-analysis
          path: |
            spec_scout_results.json
            test_profile.txt
```

## GitLab CI Integration

```yaml
stages:
  - test
  - analysis

spec_scout_analysis:
  stage: analysis
  image: ruby:3.1
  
  before_script:
    - bundle install
    - bundle exec rails db:create
    - bundle exec rails db:migrate
    
  script:
    - bundle exec spec_scout --output json > spec_scout_results.json
    
  artifacts:
    reports:
      junit: spec_scout_results.json
    paths:
      - spec_scout_results.json
    expire_in: 1 week
    
  only:
    - merge_requests
    - main

spec_scout_enforcement:
  stage: analysis
  image: ruby:3.1
  
  before_script:
    - bundle install
    - bundle exec rails db:create
    - bundle exec rails db:migrate
    
  script:
    - bundle exec spec_scout --enforce --fail-on-high-confidence
    
  allow_failure: false
  
  only:
    - main
```

## Configuration for CI

### Environment-Specific Configuration

```ruby
# config/spec_scout.rb
SpecScout.configure do |config|
  config.enable = true
  config.use_test_prof = true
  
  if ENV['CI']
    # CI-specific configuration
    config.output_format = :json
    config.enforcement_mode = ENV['SPEC_SCOUT_ENFORCE'] == 'true'
    config.fail_on_high_confidence = ENV['SPEC_SCOUT_FAIL_ON_HIGH'] == 'true'
    
    # Focus on performance-critical agents in CI
    config.enabled_agents = [:database, :factory]
  else
    # Development configuration
    config.output_format = :console
    config.enforcement_mode = false
    config.enabled_agents = [:database, :factory, :intent, :risk]
  end
end
```

### Environment Variables

Set these in your CI environment:

```bash
# Enable enforcement mode
SPEC_SCOUT_ENFORCE=true

# Fail on high confidence recommendations
SPEC_SCOUT_FAIL_ON_HIGH=true

# Enable debug output
SPEC_SCOUT_DEBUG=true

# Disable SpecScout entirely (for debugging CI issues)
SPEC_SCOUT_DISABLE=true
```

## Processing Results

### JSON Output Processing

```bash
#!/bin/bash
# process_spec_scout_results.sh

RESULTS_FILE="spec_scout_results.json"

if [ ! -f "$RESULTS_FILE" ]; then
  echo "No SpecScout results found"
  exit 0
fi

# Extract high confidence recommendations
HIGH_CONFIDENCE=$(jq -r 'select(.confidence == "high")' "$RESULTS_FILE")

if [ -n "$HIGH_CONFIDENCE" ]; then
  echo "High confidence optimizations found:"
  echo "$HIGH_CONFIDENCE" | jq -r '.spec_location + ": " + .action'
  
  # Fail if enforcement is enabled
  if [ "$SPEC_SCOUT_ENFORCE" = "true" ]; then
    exit 1
  fi
else
  echo "No high confidence optimizations found"
fi

# Generate summary
TOTAL_RECOMMENDATIONS=$(jq -r 'length' "$RESULTS_FILE")
echo "Total recommendations: $TOTAL_RECOMMENDATIONS"
```

### Pull Request Comments

```yaml
- name: Comment PR with SpecScout Results
  uses: actions/github-script@v6
  if: github.event_name == 'pull_request'
  with:
    script: |
      const fs = require('fs');
      
      if (!fs.existsSync('spec_scout_results.json')) {
        return;
      }
      
      const results = JSON.parse(fs.readFileSync('spec_scout_results.json', 'utf8'));
      
      if (results.confidence === 'high') {
        const comment = `## SpecScout Analysis
        
        High confidence optimization found in \`${results.spec_location}\`:
        
        **Recommendation:** ${results.action}
        **Confidence:** ${results.confidence}
        
        **Reasoning:**
        ${results.explanation.map(e => `- ${e}`).join('\n')}
        
        Consider applying this optimization to improve test performance.`;
        
        github.rest.issues.createComment({
          issue_number: context.issue.number,
          owner: context.repo.owner,
          repo: context.repo.repo,
          body: comment
        });
      }
```

## Best Practices for CI

### 1. Gradual Rollout
- Start with analysis-only mode
- Monitor results for several weeks
- Enable enforcement gradually

### 2. Performance Baselines
- Track test suite performance over time
- Set up alerts for performance regressions
- Use SpecScout data to identify trends

### 3. Team Communication
- Share SpecScout results in code reviews
- Document optimization decisions
- Train team on interpreting results

### 4. Maintenance
- Regularly review CI configuration
- Update SpecScout version
- Monitor for false positives

## Troubleshooting CI Issues

### Common Problems

1. **TestProf not working in CI**
   - Ensure database is properly set up
   - Check Rails environment configuration
   - Verify TestProf dependencies

2. **SpecScout timing out**
   - Reduce enabled agents
   - Focus on specific spec files
   - Increase CI timeout limits

3. **False positives in enforcement**
   - Review agent configuration
   - Consider test-specific context
   - Adjust confidence thresholds

### Debug Commands

```bash
# Test TestProf integration
bundle exec rspec --profile

# Test SpecScout with debug output
SPEC_SCOUT_DEBUG=1 bundle exec spec_scout

# Validate configuration
bundle exec ruby -e "require 'spec_scout'; puts SpecScout.configuration.to_h"
```