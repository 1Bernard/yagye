defmodule Simulator.Web.Layouts do
  use Phoenix.Component

  def admin(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>Yagye Gateway Simulator</title>
        <script src="https://cdn.jsdelivr.net/npm/phoenix@1.8.12/priv/static/phoenix.min.js">
        </script>
        <script src="https://cdn.jsdelivr.net/npm/phoenix_live_view@1.2.10/priv/static/phoenix_live_view.min.js">
        </script>
        <style>
          * { box-sizing: border-box; margin: 0; padding: 0; }
          body { font-family: system-ui, sans-serif; background: #0a0e1a; color: #e2e8f0; }

          /* ── Navigation ──────────────────────────────────────────────────── */
          .site-nav {
            background: #0f172a;
            border-bottom: 1px solid #1e293b;
            padding: 0 2rem;
            display: flex;
            align-items: center;
            gap: 2rem;
            height: 48px;
          }
          .site-nav .brand {
            font-size: .8rem;
            font-weight: 700;
            color: #475569;
            letter-spacing: .08em;
            text-transform: uppercase;
            text-decoration: none;
            margin-right: .5rem;
          }
          .site-nav a {
            font-size: .85rem;
            color: #64748b;
            text-decoration: none;
            padding: .25rem 0;
            border-bottom: 2px solid transparent;
          }
          .site-nav a:hover { color: #cbd5e1; }
          .site-nav a.active { color: #e2e8f0; border-bottom-color: #0ea5e9; }

          /* ── Page shell ──────────────────────────────────────────────────── */
          .admin-page { max-width: 1200px; margin: 0 auto; padding: 2rem; }
          .page-header { margin-bottom: 2rem; }
          .page-header h1 { font-size: 1.5rem; font-weight: 700; color: #f8fafc; }
          .page-header .subtitle { margin-top: .35rem; color: #64748b; font-size: .85rem; }
          section { margin-bottom: 2.5rem; }
          h2 { font-size: .875rem; font-weight: 600; color: #64748b; letter-spacing: .06em; text-transform: uppercase; margin-bottom: 1rem; }

          /* ── Tables ──────────────────────────────────────────────────────── */
          table { width: 100%; border-collapse: collapse; font-size: .875rem; }
          th { text-align: left; padding: .5rem .75rem; color: #475569; font-size: .75rem; font-weight: 500; letter-spacing: .05em; text-transform: uppercase; border-bottom: 1px solid #1e293b; }
          td { padding: .6rem .75rem; border-bottom: 1px solid #1a2234; vertical-align: middle; }
          tr:last-child td { border-bottom: none; }
          .row-default td { background: #111827; }

          /* ── Buttons ─────────────────────────────────────────────────────── */
          .btn-resend {
            font-size: .7rem; padding: .25rem .6rem; border-radius: 4px;
            border: 1px solid #1e293b; background: transparent; color: #475569;
            cursor: pointer;
          }
          .btn-resend:hover { border-color: #0369a1; color: #7dd3fc; }
          .btn-edit, .btn-default, .btn-save, .btn-cancel {
            font-size: .75rem; padding: .3rem .7rem; border-radius: 4px;
            border: none; cursor: pointer; margin-right: .3rem;
          }
          .btn-edit    { background: #1e293b; color: #94a3b8; }
          .btn-edit:hover { background: #263448; }
          .btn-default { background: #0369a1; color: #e0f2fe; }
          .btn-save    { background: #15803d; color: #dcfce7; }
          .btn-cancel  { background: #1e293b; color: #64748b; }

          /* ── Badges ──────────────────────────────────────────────────────── */
          .badge {
            display: inline-block; font-size: .7rem; font-weight: 600;
            padding: 2px 7px; border-radius: 3px; letter-spacing: .04em;
          }
          .badge-default   { background: #0c4a6e; color: #7dd3fc; }
          .badge-authorised, .badge-captured, .badge-partially-captured
                           { background: #14532d; color: #86efac; }
          .badge-declined  { background: #7f1d1d; color: #fca5a5; }
          .badge-pending   { background: #713f12; color: #fcd34d; }
          .badge-voided, .badge-auth-expired, .badge-reversed
                           { background: #1e293b; color: #64748b; }
          .chip {
            display: inline-block; font-size: .7rem; padding: 1px 6px;
            border-radius: 3px; font-weight: 500;
          }
          .chip-wallet     { background: #312e81; color: #a5b4fc; }
          .chip-card       { background: #1e293b; color: #94a3b8; }
          .chip-bank       { background: #1c3a2f; color: #6ee7b7; }
          .chip-mtn        { background: #422006; color: #fed7aa; }
          .chip-telecel    { background: #1e3a5f; color: #93c5fd; }
          .chip-airteltigo { background: #3b1f5e; color: #c4b5fd; }

          /* ── Scenario edit inline ────────────────────────────────────────── */
          .badge-default-s { font-size: .7rem; background: #0c4a6e; color: #7dd3fc; border-radius: 3px; padding: 1px 5px; margin-left: .4rem; }
          .edit-row td { background: #0f172a; padding: 1rem; }
          .scenario-form { width: 100%; }
          .form-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: .75rem; margin-bottom: 1rem; }
          .form-field label { display: block; font-size: .75rem; color: #64748b; margin-bottom: .25rem; }
          .input-rate, .input-int {
            width: 100%; background: #0a0e1a; border: 1px solid #1e293b;
            border-radius: 4px; color: #e2e8f0; padding: .35rem .5rem; font-size: .85rem;
          }
          .input-rate:focus, .input-int:focus { outline: none; border-color: #0369a1; }
          .form-actions { display: flex; gap: .5rem; }

          /* ── Outcome bars ────────────────────────────────────────────────── */
          .outcome-bars { display: flex; flex-direction: column; gap: .5rem; }
          .outcome-bar { display: flex; align-items: center; gap: .75rem; }
          .outcome-label { width: 90px; font-size: .8rem; color: #64748b; }
          .bar-track { flex: 1; background: #1e293b; border-radius: 3px; height: 16px; overflow: hidden; }
          .bar-fill { height: 100%; border-radius: 3px; transition: width .5s ease; }
          .outcome-count { width: 36px; font-size: .8rem; color: #475569; text-align: right; font-variant-numeric: tabular-nums; }
          .outcome-total { margin-top: .5rem; font-size: .75rem; color: #334155; }
          .refresh-note { font-size: .7rem; color: #334155; font-weight: 400; margin-left: .5rem; }

          /* ── Charge feed specific ────────────────────────────────────────── */
          .mono { font-family: ui-monospace, monospace; font-size: .8rem; color: #94a3b8; }
          .decline-code { font-size: .75rem; color: #ef4444; font-family: ui-monospace, monospace; }
          .msisdn-cell { font-size: .8rem; color: #94a3b8; }
          .msisdn-cell .network { font-size: .7rem; color: #475569; margin-left: .4rem; }
          .amount-cell { font-variant-numeric: tabular-nums; font-size: .875rem; }
          .time-cell { font-size: .75rem; color: #475569; white-space: nowrap; font-variant-numeric: tabular-nums; }
          .live-dot {
            display: inline-block; width: 7px; height: 7px;
            background: #22c55e; border-radius: 50%; margin-left: .5rem;
            animation: pulse 2s infinite;
          }
          @keyframes pulse {
            0%, 100% { opacity: 1; }
            50% { opacity: .3; }
          }

          /* ── Flash ───────────────────────────────────────────────────────── */
          .flash { padding: .6rem 1rem; border-radius: 4px; margin-bottom: 1rem; font-size: .875rem; }
          .flash-info  { background: #0c4a6e; color: #7dd3fc; }
          .flash-error { background: #7f1d1d; color: #fca5a5; }

          /* ── Empty state ─────────────────────────────────────────────────── */
          .empty-state { text-align: center; padding: 3rem; color: #334155; font-size: .875rem; }
        </style>
      </head>
      <body>
        <nav class="site-nav">
          <a href="/admin/scenarios" class="brand">Simulator</a>
          <a href="/admin/scenarios">Scenarios</a>
          <a href="/admin/charges">Charges</a>
          <a href="/admin/test-data">Test Data</a>
        </nav>
        {@inner_content}
        <script>
          var csrfToken = document.querySelector("meta[name='csrf-token']") &&
                          document.querySelector("meta[name='csrf-token']").getAttribute("content");
          var liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {params: {_csrf_token: csrfToken}});
          liveSocket.connect();
          window.liveSocket = liveSocket;

          // Mark active nav link
          (function() {
            var path = window.location.pathname;
            document.querySelectorAll(".site-nav a").forEach(function(a) {
              if (a.getAttribute("href") === path) a.classList.add("active");
            });
          })();
        </script>
      </body>
    </html>
    """
  end
end
