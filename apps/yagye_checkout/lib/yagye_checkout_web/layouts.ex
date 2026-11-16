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
        <script src="https://cdn.jsdelivr.net/npm/phoenix_live_view@1.2.11/priv/static/phoenix_live_view.min.js">
        </script>
        <script src="https://js.stripe.com/v3/"></script>
        <link rel="stylesheet" href="/assets/checkout.css" />
      </head>
      <body>
        {@inner_content}
        <script>
          var csrfToken = document.querySelector("meta[name='csrf-token']")
                            .getAttribute("content");

          // ── LiveView Hooks ───────────────────────────────────────────────
          var Hooks = {};

          // StripeCard hook: mounts Stripe Elements on a div that carries
          // data-stripe-pk. The server pushes "stripe_tokenize" to trigger
          // payment-method creation; the hook pushes "stripe_pm_ready" or
          // "stripe_error" back to the LiveView.
          Hooks.StripeCard = {
            _stripeReady: false,
            mounted: function() { this._setup(); },
            updated: function() { if (!this._stripeReady) this._setup(); },
            _setup: function() {
              var self = this;
              var pk = self.el.dataset.stripePk;
              if (!pk) return;
              function tryInit() {
                if (typeof Stripe === "undefined") { setTimeout(tryInit, 50); return; }
                if (self._stripeReady) return;
                self._stripeReady = true;
                self.stripe = Stripe(pk);
                var elements = self.stripe.elements();
                self.cardElement = elements.create("card", {
                  style: {
                    base: {
                      fontFamily: "Inter, system-ui, sans-serif",
                      fontSize: "14px",
                      color: "#111827",
                      "::placeholder": { color: "#9ca3af" }
                    },
                    invalid: { color: "#ef4444" }
                  }
                });
                self.cardElement.mount(self.el.querySelector("#stripe-card-element"));
                self.handleEvent("stripe_tokenize", function() {
                  self.stripe.createPaymentMethod({ type: "card", card: self.cardElement })
                    .then(function(result) {
                      if (result.error) {
                        self.pushEvent("stripe_error", { message: result.error.message });
                      } else {
                        self.pushEvent("stripe_pm_ready", { payment_method_id: result.paymentMethod.id });
                      }
                    });
                });
              }
              tryInit();
            }
          };

          var liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
            params: { _csrf_token: csrfToken },
            hooks: Hooks
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
