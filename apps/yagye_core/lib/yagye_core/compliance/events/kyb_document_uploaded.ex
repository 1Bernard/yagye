defmodule YagyeCore.Compliance.Events.KybDocumentUploaded do
  @moduledoc false
  @enforce_keys [:document_id, :merchant_id, :kind, :s3_key, :uploaded_by, :occurred_at]
  defstruct [:document_id, :merchant_id, :kind, :s3_key, :uploaded_by, :occurred_at]
end
