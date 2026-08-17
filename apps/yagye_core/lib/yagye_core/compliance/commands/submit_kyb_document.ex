defmodule YagyeCore.Compliance.Commands.SubmitKybDocument do
  @moduledoc false
  @enforce_keys [:merchant_id, :kind, :s3_key, :checksum, :uploaded_by]
  defstruct [:merchant_id, :kind, :s3_key, :checksum, :uploaded_by]
end
