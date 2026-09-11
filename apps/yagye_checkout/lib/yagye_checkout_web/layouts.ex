defmodule YagyeCheckoutWeb.Layouts do
  use Phoenix.Component

  def checkout(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <meta name="csrf-token" content={Plug.CSRFProtection.get_csrf_token()} />
        <title>Yagye Pay</title>
        <link
          rel="stylesheet"
          href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&family=Plus+Jakarta+Sans:wght@700;800&display=swap"
        />
        <script src="https://cdn.jsdelivr.net/npm/phoenix@1.8.12/priv/static/phoenix.min.js">
        </script>
        <script src="https://cdn.jsdelivr.net/npm/phoenix_live_view@1.2.10/priv/static/phoenix_live_view.min.js">
        </script>
        <style>
          /* Checkout is always light — dark mode is disabled intentionally.
             Trust psychology: users expect payment forms to be clean white.
             Merchant brand customisation (accent color, logo) is the planned
             personalisation surface, not dark/light toggling. */
          :root {
            --page-bg:    #F9FAFB;
            --card-bg:    #FFFFFF;
            --border:     #F3F4F6;
            --border-med: #E5E7EB;
            --ink:        #111827;
            --body-text:  #374151;
            --muted-text: #6B7280;
            --subtle-text:#9CA3AF;
            --faint-text: #D1D5DB;
            --accent:     #3D47F5;
            --input-bg:   #F9FAFB;
            --error:      #DC2626;
            --error-bg:   #FEF2F2;
            --error-bdr:  #FECACA;
            --success:    #059669;
            --success-bg: #ECFDF5;
            --success-bdr:#A7F3D0;
          }

          *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

          body {
            font-family: "Inter", system-ui, -apple-system, sans-serif;
            background: var(--page-bg);
            color: var(--ink);
            min-height: 100svh;
            margin: 0;
            padding: 2rem 1.25rem 4rem;
            display: flex;
            flex-direction: column;
            align-items: center;
          }

          @media (max-width: 640px) {
            body { padding: 1rem 0.75rem 3rem; }
          }
        </style>
      </head>
      <body>
        {@inner_content}
        <script>
          var csrfToken = document.querySelector("meta[name='csrf-token']")
                            .getAttribute("content");
          var liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
            params: { _csrf_token: csrfToken }
          });
          liveSocket.connect();
          window.liveSocket = liveSocket;

          // ── Confetti ─────────────────────────────────────────────────────
          function launchConfetti() {
            var canvas = document.createElement("canvas");
            canvas.style.cssText = "position:fixed;inset:0;width:100%;height:100%;pointer-events:none;z-index:9999";
            document.body.appendChild(canvas);
            var ctx = canvas.getContext("2d");
            canvas.width  = window.innerWidth;
            canvas.height = window.innerHeight;

            var colors = ["#3D47F5","#059669","#F59E0B","#EC4899","#10B981","#A78BFA","#FFFFFF"];
            var pieces = [];
            for (var i = 0; i < 140; i++) {
              pieces.push({
                x: Math.random() * canvas.width,
                y: -10 - Math.random() * 250,
                w: 7 + Math.random() * 7,
                h: 4 + Math.random() * 4,
                color: colors[Math.floor(Math.random() * colors.length)],
                vx: (Math.random() - 0.5) * 4,
                vy: 2.5 + Math.random() * 4,
                angle: Math.random() * Math.PI * 2,
                va: (Math.random() - 0.5) * 0.18
              });
            }

            var end = Date.now() + 3200;
            function draw() {
              ctx.clearRect(0, 0, canvas.width, canvas.height);
              var now = Date.now();
              var remaining = Math.max(0, end - now);
              pieces.forEach(function(p) {
                p.x += p.vx; p.y += p.vy; p.vy += 0.09; p.angle += p.va;
                ctx.save();
                ctx.globalAlpha = remaining < 700 ? remaining / 700 : 1;
                ctx.translate(p.x, p.y);
                ctx.rotate(p.angle);
                ctx.fillStyle = p.color;
                ctx.fillRect(-p.w/2, -p.h/2, p.w, p.h);
                ctx.restore();
              });
              if (now < end) { requestAnimationFrame(draw); } else { canvas.remove(); }
            }
            requestAnimationFrame(draw);
          }

          window.addEventListener("phx:confetti", launchConfetti);
          window.addEventListener("phx:redirect_to", function(e) {
            window.location.href = e.detail.url;
          });
        </script>
      </body>
    </html>
    """
  end
end
