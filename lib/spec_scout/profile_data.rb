# frozen_string_literal: true

module SpecScout
  # Normalized profile data structure containing test execution metrics,
  # factory usage, and database interactions extracted from TestProf
  ProfileData = Struct.new(
    :example_location, # String: "spec/models/user_spec.rb:42"
    :spec_type,          # Symbol: :model, :controller, :integration
    :runtime_ms,         # Numeric: 38
    :factories,          # Hash: { user: { strategy: :create, count: 1 } }
    :db,                 # Hash: { total_queries: 6, inserts: 1, selects: 5 }
    :events,             # Hash: EventProf data
    :metadata,           # Hash: Additional context
    keyword_init: true
  ) do
    def initialize(**args)
      super
      self.example_location ||= ''
      self.spec_type ||= :unknown
      self.runtime_ms ||= 0
      self.factories ||= {}
      self.db ||= {}
      self.events ||= {}
      self.metadata ||= {}
    end

    def valid?
      example_location.is_a?(String) &&
        spec_type.is_a?(Symbol) &&
        runtime_ms.is_a?(Numeric) &&
        factories.is_a?(Hash) &&
        db.is_a?(Hash) &&
        events.is_a?(Hash) &&
        metadata.is_a?(Hash)
    end
  end
end
