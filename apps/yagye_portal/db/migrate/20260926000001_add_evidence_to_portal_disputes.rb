# frozen_string_literal: true

class AddEvidenceToPortalDisputes < ActiveRecord::Migration[8.0]
  def change
    add_column :portal_disputes, :evidence_text,        :text
    add_column :portal_disputes, :evidence_submitted_at, :datetime
  end
end
