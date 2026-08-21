defmodule Simulator do
  @moduledoc """
  Gateway Simulator — pretends to be an external payment provider.

  Vocabulary is deliberately NOT Yagye's:
    charge_ref   (not payment_id)
    AUTHORISED   (not authorised / succeeded)
    PENDING_AUTH (not requires_action)
    DECLINED     (not failed)

  If any of these appear inside YagyeCore.Payments, the anti-corruption
  layer has failed and CI will surface it.

  Admin UI  : http://localhost:4100/admin/scenarios
  API docs  : http://localhost:4100/api/swaggerui
  """
end
