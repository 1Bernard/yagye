defmodule Mix.Tasks.Simulator.GenerateLoad do
  use Mix.Task

  @shortdoc "Fire synthetic payments at Core API to produce labeled ML training data"

  @moduledoc """
  Generates synthetic payment load by firing real requests through the Core payment
  pipeline. Each payment uses a deterministic MSISDN that maps to a known outcome
  in the simulator's outcome engine, producing labeled JSONL suitable for ML training.

  ## Usage

      mix simulator.generate_load [options]

  ## Options

      --count N            Total payments to fire (default: 1000)
      --concurrency C      Max concurrent requests (default: 20)
      --core-url URL       Core base URL (default: http://localhost:4000)
      --api-key KEY        Merchant API key (default: LOAD_GEN_API_KEY env)
      --service-token TOK  Internal service token (default: LOAD_GEN_SERVICE_TOKEN env)
      --output PATH        JSONL output file path (default: load_gen_<timestamp>.jsonl)
      --mode MODE          Payment mode: simulation|live (default: simulation)
      --amount AMOUNT      Payment amount in major units e.g. 10.00 (default: 10.00)
      --currency GHS       ISO 4217 currency code (default: GHS)

  ## Outcome distribution

  Fixed MSISDNs produce deterministic outcomes:

    - success (60%)         — 0241000001 MTN, 0501000001 TELECEL, 0571000001 AIRTELTIGO
    - insufficient_funds (15%) — 0241000002 MTN, 0501000002 TELECEL
    - expired (5%)          — 0241000003 MTN
    - not_registered (5%)   — 0241000004 MTN
    - scenario_driven (15%) — random MTN MSISDN, outcome follows active scenario rates

  Each JSONL record has: payment_id, msisdn, network, outcome_class, amount, currency,
  merchant_reference, fired_at, core_state (terminal state from polling), latency_ms.

  ## Target

  50k events in < 2 minutes with --concurrency 50.
  """

  @msisdn_distribution [
    # {weight, class, msisdn, network}
    {30, "success",            "0241000001", "MTN"},
    {15, "success",            "0501000001", "TELECEL"},
    {15, "success",            "0571000001", "AIRTELTIGO"},
    {10, "insufficient_funds", "0241000002", "MTN"},
    {5,  "insufficient_funds", "0501000002", "TELECEL"},
    {5,  "expired",            "0241000003", "MTN"},
    {5,  "not_registered",     "0241000004", "MTN"},
    {15, "scenario_driven",    nil,          "MTN"}
  ]

  @total_weight Enum.reduce(@msisdn_distribution, 0, fn {w, _, _, _}, acc -> acc + w end)

  @default_count 1000
  @default_concurrency 20
  @default_core_url "http://localhost:4000"
  @default_amount 10.00
  @default_currency "GHS"
  @default_mode "simulation"

  @poll_interval_ms 200
  @poll_max_attempts 50

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          count:         :integer,
          concurrency:   :integer,
          core_url:      :string,
          api_key:       :string,
          service_token: :string,
          output:        :string,
          mode:          :string,
          amount:        :float,
          currency:      :string
        ]
      )

    count         = opts[:count]         || @default_count
    concurrency   = opts[:concurrency]   || @default_concurrency
    core_url      = opts[:core_url]      || @default_core_url
    api_key       = opts[:api_key]       || System.get_env("LOAD_GEN_API_KEY") || raise_missing("--api-key or LOAD_GEN_API_KEY")
    service_token = opts[:service_token] || System.get_env("LOAD_GEN_SERVICE_TOKEN") || raise_missing("--service-token or LOAD_GEN_SERVICE_TOKEN")
    mode          = opts[:mode]          || @default_mode
    amount_major  = opts[:amount]        || @default_amount
    currency      = opts[:currency]      || @default_currency
    output_path   = opts[:output]        || "load_gen_#{:os.system_time(:second)}.jsonl"

    amount_minor = round(amount_major * 100)

    Mix.shell().info("""
    \n[load-gen] Starting synthetic load generation
      count       = #{count}
      concurrency = #{concurrency}
      core_url    = #{core_url}
      mode        = #{mode}
      amount      = #{amount_major} #{currency} (#{amount_minor} minor)
      output      = #{output_path}
    """)

    Application.ensure_all_started(:req)

    {:ok, file} = File.open(output_path, [:write, :utf8])
    counter = :counters.new(3, [])  # [succeeded, failed, total]

    jobs = build_job_list(count, mode, amount_minor, currency)

    start_ms = System.monotonic_time(:millisecond)

    jobs
    |> Task.async_stream(
      fn job ->
        result = fire_payment(job, core_url, api_key, service_token)
        :counters.add(counter, 3, 1)

        case result do
          {:ok, record} ->
            :counters.add(counter, 1, 1)
            record

          {:error, reason} ->
            :counters.add(counter, 2, 1)
            Map.put(job, :error, inspect(reason))
        end
      end,
      max_concurrency: concurrency,
      timeout: 30_000,
      on_timeout: :kill_task,
      ordered: false
    )
    |> Stream.each(fn
      {:ok, record} ->
        IO.write(file, Jason.encode!(record) <> "\n")
        total = :counters.get(counter, 3)
        if rem(total, max(div(count, 20), 1)) == 0, do: print_progress(counter, count, start_ms)

      {:exit, reason} ->
        :counters.add(counter, 2, 1)
        IO.write(file, Jason.encode!(%{error: inspect(reason)}) <> "\n")
    end)
    |> Stream.run()

    elapsed_s = (System.monotonic_time(:millisecond) - start_ms) / 1000

    File.close(file)

    Mix.shell().info("""
    \n[load-gen] Done in #{Float.round(elapsed_s, 1)}s
      succeeded = #{:counters.get(counter, 1)}
      failed    = #{:counters.get(counter, 2)}
      total     = #{:counters.get(counter, 3)}
      output    = #{output_path}
      rate      = #{Float.round(count / elapsed_s, 1)} payments/s
    """)
  end

  # ── Job list ─────────────────────────────────────────────────────────────────

  defp build_job_list(count, mode, amount_minor, currency) do
    Enum.map(1..count, fn i ->
      {class, msisdn, network} = pick_outcome(i)

      # Use a rotating random MSISDN for scenario_driven jobs
      effective_msisdn = msisdn || random_mtn_msisdn(i)

      %{
        index:     i,
        class:     class,
        msisdn:    effective_msisdn,
        network:   network,
        amount:    amount_minor,
        currency:  currency,
        mode:      mode,
        ref:       "loadgen_#{:os.system_time(:nanosecond)}_#{i}"
      }
    end)
  end

  defp pick_outcome(seed) do
    roll = rem(seed * 1_000_003, @total_weight)

    {class, msisdn, network} =
      Enum.reduce_while(@msisdn_distribution, roll, fn {w, class, msisdn, network}, rem ->
        if rem < w do
          {:halt, {class, msisdn, network}}
        else
          {:cont, rem - w}
        end
      end)

    {class, msisdn, network}
  end

  # Generates an MTN MSISDN that will go through scenario-rate distribution.
  # Avoids the fixed MSISDN suffixes 0001-0006 to prevent deterministic mapping.
  defp random_mtn_msisdn(seed) do
    suffix = rem(seed * 7_919 + 7, 9_000) + 1_000  # 1000-9999, avoids 000x range
    "0241#{String.pad_leading(to_string(suffix), 4, "0")}"
  end

  # ── Payment firing ────────────────────────────────────────────────────────────

  defp fire_payment(job, core_url, api_key, service_token) do
    fired_at = DateTime.utc_now()
    t0 = System.monotonic_time(:millisecond)

    with {:ok, session_id} <- create_checkout_session(job, core_url, api_key),
         {:ok, payment_id} <- submit_payment(session_id, job, core_url, service_token),
         {:ok, terminal_state} <- poll_payment_state(payment_id, core_url, service_token) do
      latency_ms = System.monotonic_time(:millisecond) - t0

      record = %{
        payment_id:          payment_id,
        session_id:          session_id,
        outcome_class:       job.class,
        msisdn:              job.msisdn,
        network:             job.network,
        amount:              job.amount,
        currency:            job.currency,
        mode:                job.mode,
        merchant_reference:  job.ref,
        fired_at:            DateTime.to_iso8601(fired_at),
        terminal_state:      terminal_state,
        latency_ms:          latency_ms
      }

      {:ok, record}
    end
  end

  defp create_checkout_session(job, core_url, api_key) do
    body = %{
      amount:             job.amount,
      currency:           job.currency,
      merchant_reference: job.ref,
      description:        "Load gen payment #{job.index}",
      metadata:           %{outcome_class: job.class, generator: "load_gen"}
    }

    case Req.post(
           core_url <> "/v1/checkout-sessions",
           json: body,
           headers: [{"authorization", "Bearer #{api_key}"}],
           receive_timeout: 10_000
         ) do
      {:ok, %Req.Response{status: 201, body: %{"id" => session_id}}} ->
        {:ok, session_id}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:session_create_failed, status, body}}

      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  defp submit_payment(session_id, job, core_url, service_token) do
    body = %{
      method:  "mobile_money",
      msisdn:  job.msisdn,
      network: job.network
    }

    case Req.post(
           core_url <> "/internal/checkout/sessions/#{session_id}/pay",
           json: body,
           headers: [
             {"x-service-name", "load_gen"},
             {"x-service-token", service_token}
           ],
           receive_timeout: 10_000
         ) do
      {:ok, %Req.Response{status: 200, body: %{"payment_public_id" => payment_id}}} ->
        {:ok, payment_id}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, {:pay_failed, status, body}}

      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  defp poll_payment_state(payment_id, core_url, service_token) do
    do_poll(payment_id, core_url, service_token, @poll_max_attempts)
  end

  defp do_poll(_payment_id, _core_url, _service_token, 0) do
    {:ok, "timeout"}
  end

  defp do_poll(payment_id, core_url, service_token, attempts_left) do
    case Req.get(
           core_url <> "/internal/checkout/payments/#{payment_id}/state",
           headers: [
             {"x-service-name", "load_gen"},
             {"x-service-token", service_token}
           ],
           receive_timeout: 5_000
         ) do
      {:ok, %Req.Response{status: 200, body: %{"state" => state}}} ->
        if terminal_state?(state) do
          {:ok, state}
        else
          Process.sleep(@poll_interval_ms)
          do_poll(payment_id, core_url, service_token, attempts_left - 1)
        end

      {:ok, %Req.Response{status: status}} ->
        {:error, {:poll_failed, status}}

      {:error, reason} ->
        {:error, {:network_error, reason}}
    end
  end

  defp terminal_state?(state) when state in ~w[succeeded failed cancelled indeterminate], do: true
  defp terminal_state?(_), do: false

  # ── Progress ──────────────────────────────────────────────────────────────────

  defp print_progress(counter, total, start_ms) do
    done       = :counters.get(counter, 3)
    succeeded  = :counters.get(counter, 1)
    failed     = :counters.get(counter, 2)
    elapsed_ms = System.monotonic_time(:millisecond) - start_ms
    rate       = if elapsed_ms > 0, do: Float.round(done / (elapsed_ms / 1000), 1), else: 0.0
    pct        = Float.round(done / total * 100, 1)

    Mix.shell().info(
      "[load-gen] #{done}/#{total} (#{pct}%) | ok=#{succeeded} err=#{failed} | #{rate} req/s"
    )
  end

  defp raise_missing(name) do
    Mix.raise("#{name} is required. Provide it as a flag or environment variable.")
  end
end
