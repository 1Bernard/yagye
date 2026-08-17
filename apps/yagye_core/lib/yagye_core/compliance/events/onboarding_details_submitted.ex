defmodule YagyeCore.Compliance.Events.OnboardingDetailsSubmitted do
  @moduledoc false
  @enforce_keys [:merchant_id, :occurred_at]
  defstruct [:merchant_id, :business_type, :website_url, :occurred_at]
end
