defmodule YagyeCore.Compliance.Commands.SubmitKybDocument do
  @moduledoc false
  @enforce_keys [:merchant_id, :kind, :checksum, :uploaded_by]
  defstruct [
    :merchant_id,
    :kind,
    :label,
    :s3_key,
    :checksum,
    :uploaded_by,
    required_for_business_types: []
  ]
end
