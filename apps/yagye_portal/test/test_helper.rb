# frozen_string_literal: true

ENV["RAILS_ENV"] ||= "test"
# CoreApiClient raises if this env var is absent. Provide a test value so the
# client can be instantiated without touching a real Core server.
ENV["CORE_PORTAL_SERVICE_SECRET"] ||= "test-service-secret"

require_relative "../config/environment"
require "rails/test_help"
require "webmock/minitest"

# Seed static reference data once before any test runs.
# Roles, permissions, and the grant matrix must exist for UserRole validations
# and User#permitted? to work. These rows are committed before test transactions
# begin, so transactional rollback never removes them.
ActiveRecord::Base.transaction do
  load "#{Rails.root}/db/seeds.rb"
end

module ActiveSupport
  class TestCase
    include FactoryBot::Syntax::Methods

    # Reset Rails thread-local state between tests so Current.user,
    # Current.permissions, and Current.mode never bleed across tests.
    teardown { Current.reset }
  end
end
