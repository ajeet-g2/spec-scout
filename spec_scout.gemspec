# frozen_string_literal: true

require_relative 'lib/spec_scout/version'

Gem::Specification.new do |spec|
  spec.name = 'spec_scout'
  spec.version = SpecScout::VERSION
  spec.authors = ['Ajeet Kumar']
  spec.email = ['akv1087@gmail.com']

  spec.summary = 'Intelligent test optimization advisor built on TestProf'
  spec.description = 'Spec Scout transforms TestProf profiling data into actionable optimization recommendations using specialized agents'
  spec.homepage = 'https://github.com/ajeet-g2/spec-scout'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 2.7.0'

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'
  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/ajeet-g2/spec-scout'
  spec.metadata['changelog_uri'] = 'https://github.com/ajeet-g2/spec-scout/blob/main/CHANGELOG.md'

  # Specify which files should be added to the gem when it is released.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (f == __FILE__) || f.match(%r{\A(?:(?:bin|test|spec|features)/|\.(?:git|travis|circleci)|appveyor)})
    end
  end
  spec.bindir = 'exe'
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Runtime dependencies
  spec.add_dependency 'test-prof', '~> 1.0'

  # Development dependencies
  spec.add_development_dependency 'prop_check', '~> 0.18'
  spec.add_development_dependency 'rake', '~> 13.0'
  spec.add_development_dependency 'rspec', '~> 3.12'
  spec.add_development_dependency 'rubocop', '~> 1.21'
end
