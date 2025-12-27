# SpecScout Best Practices

This document outlines best practices for using SpecScout effectively in your Ruby on Rails projects.

## Configuration Best Practices

### 1. Environment-Specific Configuration

```ruby
# config/spec_scout.rb
SpecScout.configure do |config|
  config.enable = true
  config.use_test_prof = true
  
  case Rails.env
  when 'development'
    # Comprehensive analysis for development
    config.enabled_agents = [:database, :factory, :intent, :risk]
    config.output_format = :console
    config.enforcement_mode = false
    
  when 'test'
    # Focus on performance in test environment
    config.enabled_agents = [:database, :factory]
    config.output_format = :json
    config.enforcement_mode = false
    
  when 'ci', 'production'
    # Conservative approach for CI/production
    config.enabled_agents = [:database, :factory, :risk]
    config.output_format = :json
    config.enforcement_mode = ENV['SPEC_SCOUT_ENFORCE'] == 'true'
  end
end
```

### 2. Agent Selection Guidelines

**All Agents (Development)**
- Use for comprehensive analysis
- Good for learning and exploration
- Provides maximum insight

**Database + Factory (Performance Focus)**
- Best for CI environments
- Focuses on high-impact optimizations
- Reduces analysis time

**Database + Factory + Risk (Conservative)**
- Good for production-critical applications
- Balances performance with safety
- Recommended for teams new to SpecScout

**Custom Combinations**
```ruby
# For legacy applications with complex callbacks
config.enabled_agents = [:database, :risk]

# For new applications with clean architecture
config.enabled_agents = [:database, :factory, :intent]

# For performance-critical applications
config.enabled_agents = [:database, :factory]
```

## Applying Recommendations

### Confidence Level Guidelines

#### High Confidence (✔)
- **Action**: Apply immediately
- **Verification**: Run affected tests
- **Risk**: Very low
- **Example**: Unit tests with unnecessary database persistence

```ruby
# Safe to change immediately
# Before
let(:user) { create(:user) }

# After  
let(:user) { build_stubbed(:user) }
```

#### Medium Confidence (⚠)
- **Action**: Apply with testing
- **Verification**: Run full test suite
- **Risk**: Low to medium
- **Example**: Controller tests with mixed signals

```ruby
# Test thoroughly after change
# Before
let(:user) { create(:user) }

# After (test carefully)
let(:user) { build_stubbed(:user) }
```

#### Low Confidence (?)
- **Action**: Manual investigation required
- **Verification**: Deep analysis needed
- **Risk**: Medium to high
- **Example**: Complex integration tests with callbacks

### Batch Application Strategy

1. **Start Small**
   ```bash
   # Apply to one spec file at a time
   bundle exec spec_scout spec/models/user_spec.rb
   ```

2. **Group by Confidence**
   ```bash
   # Apply all high confidence recommendations first
   # Then medium confidence
   # Finally low confidence (with caution)
   ```

3. **Verify Incrementally**
   ```bash
   # After each change
   bundle exec rspec spec/models/user_spec.rb
   
   # After batch of changes
   bundle exec rspec
   ```

## Performance Optimization Workflow

### 1. Baseline Measurement
```bash
# Measure current performance
bundle exec rspec --profile > baseline_performance.txt

# Run SpecScout analysis
bundle exec spec_scout --output json > baseline_analysis.json
```

### 2. Apply Optimizations
```bash
# Apply high confidence recommendations
# Document changes in commit messages
git commit -m "Apply SpecScout recommendations: replace create with build_stubbed in user specs"
```

### 3. Measure Improvements
```bash
# Measure new performance
bundle exec rspec --profile > optimized_performance.txt

# Compare results
diff baseline_performance.txt optimized_performance.txt
```

### 4. Track Over Time
```ruby
# Create performance tracking script
# scripts/track_performance.rb

require 'json'
require 'time'

results = {
  timestamp: Time.now.iso8601,
  test_count: `bundle exec rspec --dry-run | grep examples`.split.first.to_i,
  total_time: `bundle exec rspec --profile | grep "Finished in"`.match(/[\d.]+/).to_s.to_f,
  spec_scout_recommendations: JSON.parse(File.read('spec_scout_results.json'))
}

File.write("performance_history/#{Date.today}.json", JSON.pretty_generate(results))
```

## Common Patterns and Solutions

### 1. Factory Strategy Optimization

**Pattern**: Unnecessary `create` usage in unit tests
```ruby
# Before (slow)
describe User do
  let(:user) { create(:user) }
  
  it "validates email format" do
    user.email = "invalid"
    expect(user).not_to be_valid
  end
end

# After (fast)
describe User do
  let(:user) { build_stubbed(:user) }
  
  it "validates email format" do
    user.email = "invalid"
    expect(user).not_to be_valid
  end
end
```

### 2. Association Handling

**Pattern**: Unnecessary association persistence
```ruby
# Before (creates both user and organization in DB)
let(:user) { create(:user, organization: create(:organization)) }

# After (only creates user in DB)
let(:user) { create(:user, organization: build_stubbed(:organization)) }

# Or even better for unit tests
let(:user) { build_stubbed(:user, organization: build_stubbed(:organization)) }
```

### 3. Callback-Safe Optimization

**Pattern**: Tests with after_commit callbacks
```ruby
# When SpecScout detects risk, investigate callbacks
class User < ApplicationRecord
  after_commit :send_welcome_email, on: :create
end

# Option 1: Test callback separately
describe User do
  let(:user) { build_stubbed(:user) }  # Safe for validation tests
  
  it "validates email" do
    user.email = "invalid"
    expect(user).not_to be_valid
  end
end

describe "User callbacks" do
  it "sends welcome email after creation" do
    expect { create(:user) }.to change { ActionMailer::Base.deliveries.count }.by(1)
  end
end

# Option 2: Stub callbacks when not testing them
before { allow_any_instance_of(User).to receive(:send_welcome_email) }
let(:user) { create(:user) }  # Now safe to optimize
```

### 4. Integration Test Boundaries

**Pattern**: Controller tests that cross boundaries
```ruby
# Before (integration-style controller test)
describe UsersController do
  let(:user) { create(:user) }
  
  it "shows user profile" do
    get :show, params: { id: user.id }
    expect(response).to be_successful
  end
end

# After (true unit-style controller test)
describe UsersController do
  let(:user) { build_stubbed(:user) }
  
  before { allow(User).to receive(:find).and_return(user) }
  
  it "shows user profile" do
    get :show, params: { id: user.id }
    expect(response).to be_successful
  end
end
```

## Team Adoption Strategies

### 1. Gradual Introduction

**Week 1-2**: Analysis only
- Run SpecScout on existing test suite
- Share results with team
- Identify high-impact opportunities

**Week 3-4**: High confidence changes
- Apply only high confidence recommendations
- Measure performance improvements
- Build team confidence

**Week 5-6**: Medium confidence changes
- Apply medium confidence recommendations carefully
- Develop team expertise in evaluation
- Document lessons learned

**Week 7+**: Full adoption
- Integrate into CI pipeline
- Enable enforcement mode gradually
- Establish team practices

### 2. Training and Documentation

**Team Training Session**
1. SpecScout overview and benefits
2. Understanding agent recommendations
3. Hands-on practice with sample specs
4. Q&A and troubleshooting

**Documentation**
- Internal wiki with team-specific guidelines
- Examples from your codebase
- Common patterns and solutions
- Troubleshooting guide

### 3. Code Review Integration

**Pull Request Template**
```markdown
## SpecScout Analysis

- [ ] Ran SpecScout on affected spec files
- [ ] Applied high confidence recommendations
- [ ] Verified all tests still pass
- [ ] Documented any skipped recommendations and reasons

**SpecScout Results:**
<!-- Paste relevant SpecScout output here -->
```

## Monitoring and Maintenance

### 1. Performance Metrics

Track these metrics over time:
- Total test suite runtime
- Number of database queries in tests
- Factory usage patterns
- SpecScout recommendation acceptance rate

### 2. Regular Reviews

**Monthly Reviews**
- Analyze performance trends
- Review skipped recommendations
- Update configuration as needed
- Share success stories with team

**Quarterly Reviews**
- Evaluate SpecScout effectiveness
- Consider new agent configurations
- Update team practices
- Plan further optimizations

### 3. Continuous Improvement

**Feedback Loop**
1. Apply recommendations
2. Measure impact
3. Document results
4. Refine approach
5. Share learnings

**Configuration Tuning**
- Adjust agent selection based on results
- Fine-tune confidence thresholds
- Customize for project-specific patterns
- Update as codebase evolves

## Troubleshooting Common Issues

### 1. False Positives

**Problem**: SpecScout recommends changes that break tests
**Solution**: 
- Enable Risk Agent
- Review test intent carefully
- Consider callback dependencies
- Use conservative configuration

### 2. Performance Regression

**Problem**: Optimizations make tests slower
**Solution**:
- Verify database setup in tests
- Check for missing test data
- Review factory definitions
- Consider test isolation issues

### 3. Team Resistance

**Problem**: Team reluctant to adopt SpecScout
**Solution**:
- Start with voluntary adoption
- Share success metrics
- Provide training and support
- Address concerns directly

### 4. CI Integration Issues

**Problem**: SpecScout fails in CI but works locally
**Solution**:
- Check CI environment configuration
- Verify TestProf setup in CI
- Review database setup
- Enable debug mode for troubleshooting