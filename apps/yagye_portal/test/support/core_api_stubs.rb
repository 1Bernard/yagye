# frozen_string_literal: true

# WebMock helpers for CoreApiClient.
#
# Include in any test class that exercises services calling CoreApiClient:
#
#   class Compliance::ApproveApplicationTest < ActiveSupport::TestCase
#     include CoreApiStubs
#   end
#
# Every stub matches on URL and HTTP method only — headers are not asserted here
# because X-Service-Token auth is already verified in CoreApiClient unit tests.
module CoreApiStubs
  CORE_API_URL = ENV.fetch("CORE_API_URL", "http://localhost:4000")

  # Stubs POST /internal/applications/:code/approve
  def stub_core_approve(application_code:, success: true)
    url = "#{CORE_API_URL}/internal/applications/#{application_code}/approve"
    if success
      stub_request(:post, url).to_return(
        status: 200,
        body: { application_code: application_code, status: "approved" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    else
      stub_request(:post, url).to_return(
        status: 422,
        body: { error: { code: "invalid_state_transition",
                         message: "Application cannot be approved from its current state" } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    end
  end

  # Stubs POST /internal/applications/:code/reject
  def stub_core_reject(application_code:, success: true)
    url = "#{CORE_API_URL}/internal/applications/#{application_code}/reject"
    if success
      stub_request(:post, url).to_return(
        status: 200,
        body: { application_code: application_code, status: "rejected" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    else
      stub_request(:post, url).to_return(
        status: 422,
        body: { error: { code: "invalid_state_transition",
                         message: "Application cannot be rejected from its current state" } }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
    end
  end

  # Stubs any POST to the given URL to raise a network timeout.
  # Use to verify that CoreApiClient maps timeouts to a failure Result.
  def stub_core_timeout(url_pattern)
    stub_request(:post, url_pattern).to_raise(Faraday::TimeoutError)
  end
end
