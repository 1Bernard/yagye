class Current < ActiveSupport::CurrentAttributes
  attribute :user
  attribute :permissions  # Set<String> — populated on first permitted? call, cleared between requests
  attribute :request_id
  attribute :user_agent
  attribute :ip_address
  attribute :mode         # "test" | "live" | nil (nil = ops sees all modes)
end
