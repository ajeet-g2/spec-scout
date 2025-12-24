# Spec Scout

Spec Scout is a Ruby gem that transforms TestProf from a profiling tool into an intelligent optimization advisor. The system wraps TestProf execution, consumes its structured output, and uses specialized agents to analyze profiling data and generate actionable recommendations.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'spec_scout'
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install spec_scout

## Usage

```ruby
require 'spec_scout'

# Configure Spec Scout
SpecScout.configure do |config|
  config.enable = true
  config.use_test_prof = true
  config.enabled_agents = [:database, :factory, :intent, :risk]
  config.output_format = :console
end

# Basic usage will be implemented in later tasks
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/specscout/spec_scout.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).