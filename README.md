# Spec Scout

[![Gem Version](https://badge.fury.io/rb/spec_scout.svg)](https://badge.fury.io/rb/spec_scout)
[![Ruby](https://github.com/ajeet-g2/spec-scout/actions/workflows/ruby.yml/badge.svg)](https://github.com/ajeet-g2/spec-scout/actions/workflows/ruby.yml)

Spec Scout is a Ruby gem that transforms TestProf from a profiling tool into an intelligent optimization advisor. The system wraps TestProf execution, consumes its structured output, and uses specialized agents to analyze profiling data and generate actionable recommendations.

## Features

- **Intelligent Analysis**: Uses specialized agents to analyze different aspects of test performance
- **TestProf Integration**: Automatically executes and consumes TestProf profiling data
- **Safe by Default**: Never auto-modifies code, provides recommendations only
- **CI-Friendly**: Non-blocking operation with configurable enforcement modes
- **Multiple Output Formats**: Console and JSON output support
- **Extensible**: Agent-based architecture supports future enhancements

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'spec_scout'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install spec_scout

## Quick Start

### Command Line Usage

```bash
# Run with default settings
spec_scout

# Analyze specific spec file
spec_scout spec/models/user_spec.rb

# Enable enforcement mode (fail on high confidence recommendations)
spec_scout --enforce

# JSON output for CI integration
spec_scout --output json

# Disable specific agents
spec_scout --disable-agent risk
```

### Programmatic Usage

```ruby
require 'spec_scout'

# Configure Spec Scout
SpecScout.configure do |config|
  config.enable = true
  config.use_test_prof = true
  config.enabled_agents = [:database, :factory, :intent, :risk]
  config.output_format = :console
end

# Analyze a specific spec file
scout = SpecScout::SpecScout.new
result = scout.analyze('spec/models/user_spec.rb')

# Access recommendation
if result[:recommendation]
  puts result[:recommendation].action
  puts result[:recommendation].confidence
  puts result[:recommendation].explanation
end
```

## Configuration

### Configuration Options

```ruby
SpecScout.configure do |config|
  # Enable/disable Spec Scout entirely
  config.enable = true

  # Enable/disable TestProf integration
  config.use_test_prof = true

  # Enable enforcement mode (fail on high confidence recommendations)
  config.enforcement_mode = false
  config.fail_on_high_confidence = false

  # Select which agents to run
  config.enabled_agents = [:database, :factory, :intent, :risk]

  # Output format (:console or :json)
  config.output_format = :console

  # Safety settings (recommended to keep false)
  config.auto_apply_enabled = false
  config.blocking_mode_enabled = false
end
```

### Environment Variables

```bash
# Enable debug output
export SPEC_SCOUT_DEBUG=1

# Disable Spec Scout entirely
export SPEC_SCOUT_DISABLE=1
```

### Command Line Options

```bash
Usage: spec_scout [options] [spec_file]

Options:
  --disable                    Disable SpecScout analysis
  --no-testprof               Disable TestProf integration
  --enforce                   Enable enforcement mode (fail on high confidence)
  --fail-on-high-confidence   Fail on high confidence recommendations
  --output FORMAT, -o FORMAT  Output format (console, json)
  --enable-agent AGENT        Enable specific agent (database, factory, intent, risk)
  --disable-agent AGENT       Disable specific agent
  --spec SPEC_FILE            Analyze specific spec file
  --version, -v               Show version
  --help, -h                  Show this help message
```

## Agents

Spec Scout uses specialized agents to analyze different aspects of test performance:

### Database Agent
Analyzes database usage patterns and identifies unnecessary persistence.

**Recommendations:**
- Avoid database persistence when not needed
- Use `build_stubbed` instead of `create` for factories
- Optimize database queries

### Factory Agent
Evaluates FactoryBot strategy appropriateness and usage patterns.

**Recommendations:**
- Switch from `create` to `build_stubbed` when persistence isn't required
- Optimize factory association strategies
- Reduce factory usage overhead

### Intent Agent
Classifies test intent and behavior patterns to ensure appropriate test boundaries.

**Recommendations:**
- Identify unit vs integration test behavior
- Ensure test boundaries match intent
- Optimize test scope and isolation

### Risk Agent
Identifies potentially unsafe optimizations that could break test functionality.

**Safety Checks:**
- Detects `after_commit` callbacks
- Identifies complex callback chains
- Flags high-risk optimization scenarios

## Output Examples

### Console Output

```
✔ Spec Scout Recommendation

spec/models/user_spec.rb:42

Summary:
- Factory :user used `create` (3x)
- DB inserts: 3, selects: 5
- Runtime: 150ms
- Type: model spec

Agent Signals:
- Database Agent: DB unnecessary (✔ HIGH)
- Factory Agent: prefer build_stubbed (⚠ MEDIUM)
- Intent Agent: unit test behavior (✔ HIGH)
- Risk Agent: safe to optimize (✔ HIGH)

Final Recommendation:
✔ Replace `create(:user)` with `build_stubbed(:user)`
Confidence: ✔ HIGH

Reasoning:
- No database persistence required for this test
- Factory creates unnecessary database records
- Test exhibits unit test behavior patterns
- No risk factors detected
```

### JSON Output

```json
{
  "spec_location": "spec/models/user_spec.rb:42",
  "action": "replace_factory_strategy",
  "from_value": "create(:user)",
  "to_value": "build_stubbed(:user)",
  "confidence": "high",
  "explanation": [
    "No database persistence required for this test",
    "Factory creates unnecessary database records",
    "Test exhibits unit test behavior patterns",
    "No risk factors detected"
  ],
  "agent_results": [
    {
      "agent_name": "database",
      "verdict": "db_unnecessary",
      "confidence": "high",
      "reasoning": "No database writes or reloads detected",
      "metadata": {}
    }
  ],
  "profile_data": {
    "example_location": "spec/models/user_spec.rb:42",
    "spec_type": "model",
    "runtime_ms": 150,
    "factories": {
      "user": {
        "strategy": "create",
        "count": 3
      }
    },
    "db": {
      "total_queries": 8,
      "inserts": 3,
      "selects": 5
    }
  },
  "metadata": {
    "timestamp": "2024-01-15T10:30:00Z",
    "spec_scout_version": "1.0.0"
  }
}
```

## CI Integration

### GitHub Actions

```yaml
name: Spec Scout Analysis

on: [push, pull_request]

jobs:
  spec_scout:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.1
          bundler-cache: true
      
      - name: Run Spec Scout
        run: |
          bundle exec spec_scout --output json > spec_scout_results.json
          
      - name: Upload results
        uses: actions/upload-artifact@v3
        with:
          name: spec-scout-results
          path: spec_scout_results.json
```

### Enforcement Mode

Enable enforcement mode to fail CI builds on high-confidence recommendations:

```bash
# Fail on high confidence recommendations
bundle exec spec_scout --enforce --fail-on-high-confidence

# Exit code 0: No high confidence recommendations
# Exit code 1: High confidence recommendations found
```

## Advanced Usage

### Custom Agent Configuration

```ruby
# Enable only specific agents
SpecScout.configure do |config|
  config.enabled_agents = [:database, :factory]  # Skip intent and risk agents
end

# Disable risky optimizations
SpecScout.configure do |config|
  config.disable_agent(:risk)  # Skip risk assessment
end
```

### Integration with RSpec

```ruby
# spec/spec_helper.rb
require 'spec_scout'

RSpec.configure do |config|
  config.before(:suite) do
    SpecScout.configure do |scout_config|
      scout_config.enable = true
      scout_config.output_format = :json
    end
  end
  
  config.after(:suite) do
    # Run Spec Scout analysis after test suite
    scout = SpecScout::SpecScout.new
    results = scout.analyze
    
    # Process results as needed
    if results[:recommendation]&.confidence == :high
      puts "High confidence optimization available!"
      puts results[:recommendation].explanation
    end
  end
end
```

### TestProf Integration

Spec Scout automatically integrates with TestProf. Ensure TestProf is configured in your test suite:

```ruby
# spec/spec_helper.rb or test/test_helper.rb
require 'test_prof'

# TestProf configuration (optional - Spec Scout will enable profiling automatically)
TestProf.configure do |config|
  config.output_dir = 'tmp/test_prof'
end
```

## Troubleshooting

### Common Issues

#### "No profile data available"
- Ensure TestProf is installed and configured
- Check that specs are actually running
- Verify TestProf integration is enabled: `config.use_test_prof = true`

#### "No agents produced results"
- Check that agents are enabled: `config.enabled_agents`
- Verify profile data contains relevant metrics
- Enable debug mode: `SPEC_SCOUT_DEBUG=1`

#### "TestProf execution failed"
- Ensure TestProf is compatible with your Ruby/Rails version
- Check TestProf configuration for conflicts
- Run TestProf directly to isolate issues: `bundle exec rspec --profile`

### Debug Mode

Enable debug output to troubleshoot issues:

```bash
SPEC_SCOUT_DEBUG=1 bundle exec spec_scout spec/models/user_spec.rb
```

Debug output includes:
- TestProf integration status
- Agent execution details
- Profile data normalization
- Consensus engine decisions

### Performance Considerations

- Spec Scout adds minimal overhead beyond TestProf execution
- Agent analysis typically takes < 2ms per example
- Large test suites (10k+ examples) are supported
- Memory usage is optimized to prevent leaks

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run unit tests only
bundle exec rspec spec/lib

# Run integration tests
bundle exec rspec spec/integration

# Run property-based tests
bundle exec rspec spec/properties
```

### Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Write tests for your changes
4. Ensure all tests pass (`bundle exec rspec`)
5. Commit your changes (`git commit -am 'Add some feature'`)
6. Push to the branch (`git push origin my-new-feature`)
7. Create a Pull Request

## Compatibility

- **Ruby**: 2.7.0 or higher
- **Rails**: 5.2 or higher (for TestProf integration)
- **TestProf**: 1.0 or higher

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Acknowledgments

- Built on top of [TestProf](https://github.com/test-prof/test-prof) by Vladimir Dementyev
- Inspired by the Ruby testing community's focus on performance optimization
