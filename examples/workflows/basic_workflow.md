# Basic SpecScout Workflow

This document outlines the recommended workflow for using SpecScout in your development process.

## Setup

1. **Install SpecScout**
   ```bash
   # Add to Gemfile
   gem 'spec_scout'
   
   # Install
   bundle install
   ```

2. **Configure SpecScout**
   ```ruby
   # spec/spec_helper.rb
   require 'spec_scout'
   
   SpecScout.configure do |config|
     config.enable = true
     config.use_test_prof = true
     config.enabled_agents = [:database, :factory, :intent, :risk]
     config.output_format = :console
   end
   ```

## Development Workflow

### Step 1: Run Your Tests Normally
```bash
# Run your test suite as usual
bundle exec rspec spec/models/user_spec.rb
```

### Step 2: Analyze with SpecScout
```bash
# Analyze specific spec file
bundle exec spec_scout spec/models/user_spec.rb

# Or analyze entire test suite
bundle exec spec_scout
```

### Step 3: Review Recommendations
SpecScout will output recommendations like:
```
✔ Spec Scout Recommendation

spec/models/user_spec.rb:42

Summary:
- Factory :user used `create` (3x)
- DB inserts: 3, selects: 5
- Runtime: 150ms

Agent Signals:
- Database Agent: DB unnecessary (✔ HIGH)
- Factory Agent: prefer build_stubbed (⚠ MEDIUM)
- Intent Agent: unit test behavior (✔ HIGH)
- Risk Agent: safe to optimize (✔ HIGH)

Final Recommendation:
✔ Replace `create(:user)` with `build_stubbed(:user)`
Confidence: ✔ HIGH
```

### Step 4: Apply Recommendations
Based on the confidence level:

**High Confidence (✔)**: Safe to apply immediately
```ruby
# Before
let(:user) { create(:user) }

# After
let(:user) { build_stubbed(:user) }
```

**Medium Confidence (⚠)**: Review and test carefully
- Apply in development environment first
- Run full test suite after changes
- Monitor for any behavioral changes

**Low Confidence (?)**: Manual investigation required
- Review the reasoning provided
- Consider the specific test context
- May require domain knowledge to decide

### Step 5: Verify Changes
```bash
# Run tests again to ensure they still pass
bundle exec rspec spec/models/user_spec.rb

# Check performance improvement
bundle exec rspec spec/models/user_spec.rb --profile
```

## Best Practices

### 1. Start Small
- Begin with high-confidence recommendations
- Apply changes to one spec file at a time
- Verify each change before moving to the next

### 2. Understand Your Tests
- Review the agent reasoning
- Consider your test's specific requirements
- Don't blindly apply all recommendations

### 3. Monitor Performance
- Measure test suite performance before and after changes
- Use TestProf directly for detailed performance analysis
- Track improvements over time

### 4. Safety First
- Always run your full test suite after applying changes
- Use version control to track changes
- Consider the risk assessment from the Risk Agent

## Common Scenarios

### Unit Tests
- High confidence for `build_stubbed` recommendations
- Focus on Database and Factory agents
- Usually safe to optimize aggressively

### Integration Tests
- More conservative approach recommended
- Pay attention to Intent Agent feedback
- Database persistence often required

### Controller Tests
- Mixed signals are common
- Consider test boundaries carefully
- May benefit from stubbing external dependencies

### System/Feature Tests
- Usually require database persistence
- Focus on factory optimization rather than strategy changes
- Consider test data setup efficiency

## Troubleshooting

### No Recommendations
- Ensure TestProf is working: `bundle exec rspec --profile`
- Check SpecScout configuration
- Verify agents are enabled

### Unexpected Recommendations
- Enable debug mode: `SPEC_SCOUT_DEBUG=1`
- Review agent reasoning
- Consider test-specific context

### Performance Regression
- Revert changes and analyze
- Check for missing test coverage
- Consider test intent vs. implementation