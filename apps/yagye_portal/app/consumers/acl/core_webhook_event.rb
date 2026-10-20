# frozen_string_literal: true

module Acl
  # Translates a raw Core webhook event payload into Portal's model language.
  #
  # Core field              → Portal column       Reason
  # ----------------------    -----------------   -------
  # public_id               → endpoint_id         Portal uses endpoint_id as the stable identifier
  # webhook_event_type      → event_type          Scoped name avoids collision with envelope event_type
  # webhook_event_id        → event_id            Same scoping convention
  # consecutive_failures    → consecutive_failures Direct mapping; name kept for clarity
  class CoreWebhookEvent
    def initialize(payload)
      @p = payload
    end

    # ── Routing ───────────────────────────────────────────────────────────────

    def event_type = @p["event_type"].to_s

    def endpoint_event? = event_type.start_with?("webhook.endpoint.")
    def delivery_event? = event_type.start_with?("webhook.delivery.")
    def deregister?     = event_type == "webhook.endpoint.deregistered"

    # ── Endpoint fields ───────────────────────────────────────────────────────

    def endpoint_id    = @p["endpoint_id"] || @p["public_id"]
    def merchant_code  = @p["merchant_code"]
    def url            = @p["url"]
    def mode           = @p["mode"] || "test"
    def active         = @p["active"] != false
    def subscribed_events      = Array(@p["subscribed_events"])
    def consecutive_failures   = @p["consecutive_failures"].to_i
    def last_event_id  = @p["event_id"].to_s

    def endpoint_valid? = endpoint_id.present?

    # ── Delivery fields ───────────────────────────────────────────────────────

    def delivery_id    = @p["delivery_id"] || @p["public_id"]
    def delivery_event_type    = @p["webhook_event_type"] || @p["event_type"]
    def delivery_event_id      = @p["webhook_event_id"]
    def state          = @p["state"] || "delivering"
    def attempt        = @p["attempt"].to_i.then { |n| n > 0 ? n : 1 }
    def response_status = @p["response_status"]
    def response_body  = @p["response_body"]
    def request_body   = @p["request_body"]
    def request_headers = @p["request_headers"]
    def duration_ms    = @p["duration_ms"]
    def delivered_at   = @p["delivered_at"]

    def delivery_valid? = delivery_id.present?
  end
end
