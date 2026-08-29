# frozen_string_literal: true

module Payments
  # P12: Dispute model is not yet built in the portal.
  # This query object is the integration point — swap the stub for
  # Dispute.all once the Dispute model lands in P12.
  class DisputesQuery
    TAB_STATUSES = {
      "open" => %w[submitted under_review],
      "won"  => %w[won],
      "lost" => %w[lost]
    }.freeze

    def initialize(relation = nil)
      @relation = relation
    end

    def call(filters = {})
      []
    end
  end
end
