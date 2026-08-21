defmodule Simulator.Web.Layouts do
  use Phoenix.Component

  def admin(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <title>Yagye Gateway Simulator</title>
        <script src="https://cdn.jsdelivr.net/npm/phoenix@1.7.14/priv/static/phoenix.min.js">
        </script>
        <script src="https://cdn.jsdelivr.net/npm/phoenix_live_view@1.0.0/priv/static/phoenix_live_view.min.js">
        </script>
        <style>
          * { box-sizing: border-box; margin: 0; padding: 0; }
          body { font-family: system-ui, sans-serif; background: #0f172a; color: #e2e8f0; }
          .admin-page { max-width: 1100px; margin: 0 auto; padding: 2rem; }
          .page-header { margin-bottom: 2rem; }
          .page-header h1 { font-size: 1.75rem; font-weight: 700; color: #f8fafc; }
          .page-header .subtitle { margin-top: .4rem; color: #94a3b8; font-size: .9rem; }
          section { margin-bottom: 2.5rem; }
          h2 { font-size: 1.1rem; font-weight: 600; color: #cbd5e1; margin-bottom: 1rem; }
          table { width: 100%; border-collapse: collapse; font-size: .875rem; }
          th { text-align: left; padding: .5rem .75rem; color: #64748b; border-bottom: 1px solid #1e293b; }
          td { padding: .6rem .75rem; border-bottom: 1px solid #1e293b; }
          .row-default td { background: #1e293b; }
          .badge-default { font-size: .7rem; background: #0ea5e9; color: #fff; border-radius: 3px; padding: 1px 5px; margin-left: .4rem; }
          .btn-edit, .btn-default, .btn-save, .btn-cancel { font-size: .8rem; padding: .3rem .7rem; border-radius: 4px; border: none; cursor: pointer; margin-right: .3rem; }
          .btn-edit { background: #334155; color: #cbd5e1; }
          .btn-default { background: #0369a1; color: #fff; }
          .btn-save { background: #16a34a; color: #fff; }
          .btn-cancel { background: #374151; color: #9ca3af; }
          .edit-row td { background: #1e293b; padding: 1rem; }
          .scenario-form { width: 100%; }
          .form-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: .75rem; margin-bottom: 1rem; }
          .form-field label { display: block; font-size: .75rem; color: #94a3b8; margin-bottom: .2rem; }
          .input-rate, .input-int { width: 100%; background: #0f172a; border: 1px solid #334155; border-radius: 4px; color: #e2e8f0; padding: .35rem .5rem; font-size: .85rem; }
          .form-actions { display: flex; gap: .5rem; }
          .outcomes-panel { }
          .outcome-bars { display: flex; flex-direction: column; gap: .5rem; }
          .outcome-bar { display: flex; align-items: center; gap: .75rem; }
          .outcome-label { width: 90px; font-size: .8rem; color: #94a3b8; }
          .bar-track { flex: 1; background: #1e293b; border-radius: 4px; height: 18px; overflow: hidden; }
          .bar-fill { height: 100%; border-radius: 4px; transition: width .5s ease; }
          .outcome-count { width: 30px; font-size: .8rem; color: #64748b; text-align: right; }
          .outcome-total { margin-top: .5rem; font-size: .75rem; color: #475569; }
          .refresh-note { font-size: .75rem; color: #475569; font-weight: 400; }
          .flash { padding: .6rem 1rem; border-radius: 4px; margin-bottom: 1rem; font-size: .875rem; }
          .flash-info { background: #164e63; color: #7dd3fc; }
          .flash-error { background: #7f1d1d; color: #fca5a5; }
        </style>
        <script>
          import { Socket } from "/phoenix";
          import { LiveSocket } from "/phoenix_live_view";
          let csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content");
          let liveSocket = new LiveSocket("/live", Socket, { params: { _csrf_token: csrfToken } });
          liveSocket.connect();
          window.liveSocket = liveSocket;
        </script>
      </head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end
end
