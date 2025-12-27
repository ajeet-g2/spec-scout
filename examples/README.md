# SpecScout Examples

This directory contains comprehensive examples and documentation for using SpecScout effectively in your Ruby on Rails projects.

## Directory Structure

```
examples/
├── configurations/          # Sample configuration files
├── sample_outputs/         # Example SpecScout outputs
├── workflows/              # Workflow documentation
├── best_practices.md       # Comprehensive best practices guide
└── README.md              # This file
```

## Quick Start

1. **Choose a Configuration**
   - [`basic_config.rb`](configurations/basic_config.rb) - Standard Rails application
   - [`ci_config.rb`](configurations/ci_config.rb) - CI/CD integration
   - [`conservative_config.rb`](configurations/conservative_config.rb) - Safety-focused
   - [`development_config.rb`](configurations/development_config.rb) - Local development
   - [`performance_focused_config.rb`](configurations/performance_focused_config.rb) - Maximum optimization

2. **Review Sample Outputs**
   - [High Confidence Console Output](sample_outputs/console_output_high_confidence.txt)
   - [Medium Confidence Console Output](sample_outputs/console_output_medium_confidence.txt)
   - [No Action Console Output](sample_outputs/console_output_no_action.txt)
   - [Risk Detected Console Output](sample_outputs/console_output_risk_detected.txt)
   - [High Confidence JSON Output](sample_outputs/json_output_high_confidence.json)
   - [No Action JSON Output](sample_outputs/json_output_no_action.json)

3. **Follow a Workflow**
   - [Basic Workflow](workflows/basic_workflow.md) - Standard development process
   - [CI Integration](workflows/ci_integration.md) - Continuous integration setup

4. **Apply Best Practices**
   - [Best Practices Guide](best_practices.md) - Comprehensive usage guidelines

## Configuration Examples

### Basic Configuration
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

### CI Configuration
```ruby
# For CI environments
SpecScout.configure do |config|
  config.enable = true
  config.use_test_prof = true
  config.enforcement_mode = true
  config.fail_on_high_confidence = true
  config.enabled_agents = [:database, :factory]
  config.output_format = :json
end
```

## Usage Examples

### Command Line
```bash
# Basic analysis
spec_scout

# Specific spec file
spec_scout spec/models/user_spec.rb

# JSON output for CI
spec_scout --output json

# Enforcement mode
spec_scout --enforce --fail-on-high-confidence

# Disable specific agents
spec_scout --disable-agent risk
```

### Programmatic Usage
```ruby
# Create SpecScout instance
scout = SpecScout::SpecScout.new

# Analyze specific spec
result = scout.analyze('spec/models/user_spec.rb')

# Process results
if result[:recommendation]
  puts "Action: #{result[:recommendation].action}"
  puts "Confidence: #{result[:recommendation].confidence}"
  puts "Explanation: #{result[:recommendation].explanation.join(', ')}"
end
```

## Sample Outputs Explained

### High Confidence Recommendation
When SpecScout finds a clear optimization opportunity:
- Multiple agents agree on the recommendation
- No risk factors detected
- Clear performance benefit available
- Safe to apply immediately

### Medium Confidence Recommendation
When SpecScout finds a potential optimization:
- Mixed signals from agents
- Some uncertainty in analysis
- Requires careful testing
- Manual review recommended

### No Action Recommendation
When SpecScout determines current implementation is optimal:
- Test requires current approach
- No performance benefit available
- Optimization would break functionality
- Current strategy is appropriate

### Risk Detected
When SpecScout identifies potential issues:
- Callbacks or side effects detected
- Optimization could break functionality
- Manual investigation required
- Conservative approach recommended

## Agent Behavior Examples

### Database Agent
```ruby
# Recommends build_stubbed when:
let(:user) { create(:user) }  # Creates DB record unnecessarily

it "validates email format" do
  user.email = "invalid"
  expect(user).not_to be_valid  # Only needs validation, not persistence
end

# Recommends keeping create when:
let(:user) { create(:user) }

it "can be found by email" do
  expect(User.find_by(email: user.email)).to eq(user)  # Requires DB persistence
end
```

### Factory Agent
```ruby
# Recommends strategy change when:
let(:user) { create(:user, posts: create_list(:post, 3)) }  # Unnecessary persistence

# Recommends keeping create when:
let(:user) { create(:user) }

after { user.posts.reload }  # Requires DB persistence for reload
```

### Intent Agent
```ruby
# Identifies unit test behavior:
# spec/models/user_spec.rb
describe User do
  it "validates presence of email" do  # Pure model validation
    user = build(:user, email: nil)
    expect(user).not_to be_valid
  end
end

# Identifies integration test behavior:
# spec/controllers/users_controller_spec.rb
describe UsersController do
  it "creates user and sends email" do  # Multiple system interactions
    post :create, params: { user: attributes }
    expect(ActionMailer::Base.deliveries).not_to be_empty
  end
end
```

### Risk Agent
```ruby
# Flags risk when callbacks are present:
class User < ApplicationRecord
  after_commit :send_welcome_email, on: :create
  after_create :update_statistics
end

# Safe optimization:
class User < ApplicationRecord
  validates :email, presence: true  # No callbacks, safe to use build_stubbed
end
```

## Integration Examples

### RSpec Integration
```ruby
# spec/spec_helper.rb
RSpec.configure do |config|
  config.after(:suite) do
    if ENV['SPEC_SCOUT_ANALYZE']
      scout = SpecScout::SpecScout.new
      results = scout.analyze
      
      if results[:recommendation]&.confidence == :high
        puts "\n🚀 SpecScout found high-confidence optimizations!"
        puts "Run 'bundle exec spec_scout' for details."
      end
    end
  end
end
```

### Rails Integration
```ruby
# config/environments/test.rb
Rails.application.configure do
  # SpecScout configuration for test environment
  config.after_initialize do
    SpecScout.configure do |scout_config|
      scout_config.enable = true
      scout_config.use_test_prof = true
      scout_config.enabled_agents = [:database, :factory]
    end
  end
end
```

### Rake Task Integration
```ruby
# lib/tasks/spec_scout.rake
namespace :spec_scout do
  desc "Analyze test suite with SpecScout"
  task analyze: :environment do
    require 'spec_scout'
    
    scout = SpecScout::SpecScout.new
    result = scout.analyze
    
    if result[:recommendation]
      puts "SpecScout Analysis Complete"
      puts "Confidence: #{result[:recommendation].confidence}"
      puts "Action: #{result[:recommendation].action}"
    else
      puts "No recommendations found"
    end
  end
  
  desc "Generate SpecScout report"
  task report: :environment do
    require 'spec_scout'
    
    SpecScout.configure { |c| c.output_format = :json }
    scout = SpecScout::SpecScout.new
    result = scout.analyze
    
    File.write('spec_scout_report.json', JSON.pretty_generate(result))
    puts "Report saved to spec_scout_report.json"
  end
end
```

## Troubleshooting Examples

### Debug Configuration
```ruby
# Enable debug mode
ENV['SPEC_SCOUT_DEBUG'] = '1'

SpecScout.configure do |config|
  config.enable = true
  config.use_test_prof = true
  
  # Log configuration for debugging
  puts "SpecScout Configuration: #{config.to_h}"
end
```

### TestProf Integration Issues
```bash
# Test TestProf directly
bundle exec rspec --profile

# Test SpecScout with minimal config
SPEC_SCOUT_DEBUG=1 bundle exec spec_scout --no-testprof
```

### Performance Debugging
```ruby
# Measure SpecScout overhead
start_time = Time.now
scout = SpecScout::SpecScout.new
result = scout.analyze('spec/models/user_spec.rb')
end_time = Time.now

puts "SpecScout analysis took: #{(end_time - start_time) * 1000}ms"
```

## Contributing Examples

When contributing to SpecScout, please include:

1. **Configuration examples** for new features
2. **Sample outputs** showing new behavior
3. **Workflow documentation** for new use cases
4. **Best practices** for new functionality

See the main [Contributing Guide](../README.md#contributing) for more details.

## Additional Resources

- [Main README](../README.md) - Complete SpecScout documentation
- [TestProf Documentation](https://test-prof.evilmartians.io/) - Underlying profiling tool
- [FactoryBot Documentation](https://github.com/thoughtbot/factory_bot) - Factory optimization context
- [RSpec Documentation](https://rspec.info/) - Testing framework integration