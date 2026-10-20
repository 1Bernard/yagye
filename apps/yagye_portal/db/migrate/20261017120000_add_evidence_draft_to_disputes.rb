# frozen_string_literal: true

class AddEvidenceDraftToDisputes < ActiveRecord::Migration[8.0]
  def change
    add_column :portal_disputes, :evidence_draft_text,  :text
    add_column :portal_disputes, :evidence_draft_by,    :text
    add_column :portal_disputes, :evidence_draft_at,    :datetime
    add_column :portal_disputes, :evidence_approved_by, :text
  end
end
