# frozen_string_literal: true

module Auth
  class TotpEnrollmentView < ApplicationComponent
    include UI::Theme

    # Branding colours for the three recommended apps
    APP_BADGES = [
      { label: "Google Authenticator", init: "G",  bg: "#4285F4" },
      { label: "Authy",                init: "A",  bg: "#ec3c44" },
      { label: "1Password",            init: "1P", bg: "#1f2d3d" }
    ].freeze

    def initialize(csrf_token:, otp_secret:, qr_svg:, user_email:)
      @csrf_token = csrf_token
      @otp_secret = otp_secret
      @qr_svg     = qr_svg
      @user_email = user_email
    end

    def view_template
      render Auth::Shell.new(
        title:    "Secure your account",
        subtitle: "Staff accounts require an authenticator app. Set it up once — it takes about 60 seconds."
      ) do
        enrollment_styles
        steps_timeline
        enrollment_form
        enrollment_script
      end
    end

    private

    # ── Styles ────────────────────────────────────────────────────────────────

    def enrollment_styles
      style do
        raw safe(<<~CSS)
          .enroll-step { display: flex; gap: 14px; }
          .enroll-step + .enroll-step { margin-top: 0; }

          .step-spine {
            display: flex; flex-direction: column; align-items: center;
            flex-shrink: 0; width: 28px;
          }
          .step-dot {
            width: 28px; height: 28px; border-radius: 50%;
            display: flex; align-items: center; justify-content: center;
            font-size: 11px; font-weight: 700; flex-shrink: 0;
            background: rgba(61,71,245,0.10); color: #3D47F5;
          }
          .step-dot.done {
            background: rgba(61,71,245,0.10); color: #3D47F5;
          }
          .step-line {
            width: 1.5px; flex: 1; min-height: 14px;
            background: linear-gradient(to bottom, #e5e7eb 0%, #e5e7eb 100%);
            margin: 3px 0;
          }
          .step-body { flex: 1; padding-bottom: 20px; }
          .step-body.last { padding-bottom: 0; }

          .app-badge {
            display: inline-flex; align-items: center; gap: 6px;
            border: 1px solid #e5e7eb; border-radius: 8px;
            padding: 5px 9px; font-size: 11.5px; font-weight: 500;
            color: #374151; background: #fff; white-space: nowrap;
          }
          .app-badge-dot {
            width: 18px; height: 18px; border-radius: 50%;
            display: flex; align-items: center; justify-content: center;
            font-size: 8px; font-weight: 800; color: #fff; flex-shrink: 0;
          }

          .qr-card {
            background: #fff; border: 1px solid #e5e7eb;
            border-radius: 14px; padding: 18px 18px 14px;
            display: flex; flex-direction: column; align-items: center;
            width: 100%;
            box-shadow: 0 1px 4px rgba(0,0,0,0.05);
          }
          .qr-card svg {
            display: block;
            width: 210px;
            height: 210px;
            border-radius: 4px;
          }

          /* Manual entry disclosure */
          details.secret-reveal summary {
            list-style: none; user-select: none; cursor: pointer;
            display: flex; align-items: center; gap: 5px;
            font-size: 11.5px; font-weight: 500; color: #6b7280;
            transition: color .15s;
          }
          details.secret-reveal summary:hover { color: #374151; }
          details.secret-reveal summary::marker,
          details.secret-reveal summary::-webkit-details-marker { display: none; }
          details.secret-reveal .chevron {
            width: 12px; height: 12px; color: currentColor; flex-shrink: 0;
            transition: transform .2s ease;
          }
          details.secret-reveal[open] .chevron { transform: rotate(90deg); }

          /* Key / account rows in manual section */
          .manual-row {
            display: flex; align-items: center; gap: 10px;
            padding: 10px 12px; font-size: 11.5px;
          }
          .manual-row + .manual-row { border-top: 1px solid #f3f4f6; }
          .manual-label {
            font-size: 10px; font-weight: 700; text-transform: uppercase;
            letter-spacing: .1em; color: #9ca3af; width: 52px; flex-shrink: 0;
          }
          .manual-value {
            flex: 1; font-family: ui-monospace, monospace;
            font-size: 12px; font-weight: 600; color: #1f2937;
            word-break: break-all; letter-spacing: .04em;
          }
          .copy-btn {
            display: inline-flex; align-items: center; justify-content: center;
            width: 26px; height: 26px; border-radius: 6px; border: 1px solid #e5e7eb;
            background: #fff; cursor: pointer; flex-shrink: 0; color: #9ca3af;
            transition: color .15s, background .15s, border-color .15s;
          }
          .copy-btn:hover { color: #3D47F5; border-color: #c7d2fe; background: #eef2ff; }
          .copy-btn.copied { color: #16a34a; border-color: #bbf7d0; background: #f0fdf4; }

          .otp-box {
            width: 44px; height: 52px;
            border: 1.5px solid #e5e7eb; border-radius: 10px;
            font-size: 24px; font-weight: 700;
            text-align: center; color: #111827;
            background: #f9fafb;
            transition: border-color .15s, box-shadow .15s, background .15s;
            outline: none; caret-color: transparent;
          }
          .otp-box:focus {
            border-color: #3D47F5; background: #fff;
            box-shadow: 0 0 0 3px rgba(61,71,245,0.12);
          }
          .otp-box.otp-filled { border-color: #3D47F5; background: #fff; }
          #enroll-submit { transition: opacity .2s; }
          #enroll-submit:disabled { opacity: .38; cursor: not-allowed; }
        CSS
      end
    end

    # ── Three-step timeline ───────────────────────────────────────────────────

    def steps_timeline
      div(class: "mb-6") do
        step_download
        step_scan
      end
    end

    def step_download
      div(class: "enroll-step") do
        div(class: "step-spine") do
          div(class: "step-dot") { plain "1" }
          div(class: "step-line")
        end
        div(class: "step-body") do
          p(class: "text-[13px] font-semibold text-gray-800 mb-[6px] mt-[4px]") do
            plain "Download an authenticator app"
          end
          p(class: "text-[12px] text-gray-400 mb-3 leading-snug") do
            plain "Any of these work — pick one you already have."
          end
          div(class: "flex flex-wrap gap-2") do
            APP_BADGES.each do |app|
              span(class: "app-badge") do
                span(class: "app-badge-dot", style: "background:#{app[:bg]}") do
                  plain app[:init]
                end
                plain app[:label]
              end
            end
          end
        end
      end
    end

    def step_scan
      div(class: "enroll-step") do
        div(class: "step-spine") do
          div(class: "step-dot") { plain "2" }
          div(class: "step-line")
        end
        div(class: "step-body") do
          p(class: "text-[13px] font-semibold text-gray-800 mb-[6px] mt-[4px]") do
            plain "Scan this QR code with your app"
          end
          p(class: "text-[12px] text-gray-400 mb-3 leading-snug") do
            plain "Open the app, tap + or Scan, then point your camera here."
          end

          # QR code card — email shown as a proper account chip
          div(class: "qr-card mb-3") do
            raw safe(scalable_qr_svg)
            # Account label beneath the QR
            div(class: "flex items-center gap-1.5 mt-2.5 px-2 py-1.5 rounded-lg",
                style: "background:#f9fafb;border:1px solid #f3f4f6") do
              span(class: "flex w-[11px] h-[11px] flex-shrink-0", style: "color:#9ca3af") do
                render UI::Icon.new(:mail, class: "w-full h-full")
              end
              span(class: "text-[11px] font-medium text-gray-500 truncate max-w-[150px]") do
                plain @user_email
              end
            end
          end

          # Manual entry fallback — styled toggle with copy buttons
          details(class: "secret-reveal") do
            summary do
              # Chevron SVG
              raw safe('<svg class="chevron" viewBox="0 0 12 12" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="4,2 8,6 4,10"/></svg>')
              plain "Can't scan? Set up manually"
            end

            div(class: "mt-2 rounded-xl overflow-hidden",
                style: "border:1px solid #f3f4f6;background:#fafafa") do
              # Account row
              div(class: "manual-row") do
                span(class: "manual-label") { plain "Account" }
                span(class: "manual-value", id: "manual-account",
                     style: "letter-spacing:0;font-size:11.5px") do
                  plain @user_email
                end
                button(type: "button", class: "copy-btn",
                       title: "Copy account name",
                       data: { copy_target: "manual-account" }) do
                  raw safe(copy_icon_svg)
                end
              end
              # Key row
              div(class: "manual-row") do
                span(class: "manual-label") { plain "Key" }
                span(class: "manual-value", id: "manual-key") do
                  plain formatted_secret
                end
                button(type: "button", class: "copy-btn",
                       title: "Copy secret key",
                       data: { copy_target: "manual-key" }) do
                  raw safe(copy_icon_svg)
                end
              end
              # Meta row
              div(class: "px-3 py-2 flex items-center gap-3",
                  style: "border-top:1px solid #f3f4f6") do
                meta_chip("Time-based")
                meta_chip("6 digits")
                meta_chip("30s interval")
              end
            end
          end
        end
      end
    end

    # ── Enrollment form (step 3 + submit) ─────────────────────────────────────

    def enrollment_form
      div(class: "enroll-step") do
        div(class: "step-spine") do
          div(class: "step-dot") { plain "3" }
        end
        div(class: "step-body last") do
          p(class: "text-[13px] font-semibold text-gray-800 mb-[6px] mt-[4px]") do
            plain "Enter the 6-digit code to confirm"
          end
          p(class: "text-[12px] text-gray-400 mb-4 leading-snug") do
            plain "Your app is now showing a rotating code. Enter it below."
          end

          form(action: users_complete_totp_enrollment_path, method: :post, id: "enroll-form") do
            input(type: "hidden", name: :authenticity_token, value: @csrf_token)
            input(type: "hidden", name: "otp_code", id: "enroll-hidden", value: "")

            # 6 individual digit boxes
            div(class: "flex gap-2 mb-5") do
              6.times do |i|
                input(
                  type:         "text",
                  maxlength:    "1",
                  inputmode:    "numeric",
                  pattern:      "[0-9]",
                  autocomplete: i.zero? ? "one-time-code" : "off",
                  autofocus:    i.zero?,
                  class:        "otp-box",
                  data:         { idx: i.to_s }
                )
              end
            end

            button(
              type:     :submit,
              id:       "enroll-submit",
              disabled: true,
              class:    "w-full inline-flex items-center justify-center rounded-xl px-4 py-3.5 " \
                        "text-sm font-semibold text-white shadow-lg",
              style:    "background-color:#3D47F5",
              data: {
                controller:                        "loading-button",
                action:                            "click->loading-button#start",
                loading_button_loading_text_value: "Activating…"
              }
            ) do
              render UI::Icon.new(:spinner, class: "w-4 h-4 mr-2 animate-spin hidden",
                                            data: { loading_button_target: "spinner" })
              span(data: { loading_button_target: "label" }) do
                render UI::Icon.new(:shield, class: "#{ICON_SM} mr-1.5 inline")
                plain "Activate two-factor authentication"
              end
            end

            div(class: "flex items-center justify-center gap-1.5 mt-3 text-gray-400") do
              render UI::Icon.new(:lock, class: "w-3 h-3")
              span(class: "text-[11px]") { plain "Verification keeps your account and your merchants safe" }
            end
          end

          div(class: "mt-5 text-center") do
            a(href: new_user_session_path,
              class: "text-[12px] #{LINK_MUTED}") do
              plain "Sign in with a different account"
            end
          end
        end
      end
    end

    # ── Inline JS (digit boxes + auto-submit) ─────────────────────────────────

    def enrollment_script
      script do
        raw safe(<<~JS)
          (function () {
            const boxes  = [...document.querySelectorAll('.otp-box')];
            const hidden = document.getElementById('enroll-hidden');
            const btn    = document.getElementById('enroll-submit');

            function sync() {
              const val = boxes.map(b => b.value).join('');
              hidden.value = val;
              boxes.forEach(b => b.classList.toggle('otp-filled', b.value !== ''));
              const ready = /^\\d{6}$/.test(val);
              btn.disabled = !ready;
              return ready;
            }

            boxes.forEach((box, i) => {
              box.addEventListener('keydown', e => {
                if (e.key === 'Backspace') {
                  e.preventDefault();
                  if (box.value !== '') { box.value = ''; }
                  else if (i > 0) { boxes[i-1].focus(); boxes[i-1].value = ''; }
                  sync();
                } else if (e.key === 'ArrowLeft'  && i > 0) { boxes[i-1].focus(); }
                  else if (e.key === 'ArrowRight' && i < 5) { boxes[i+1].focus(); }
              });

              box.addEventListener('input', e => {
                const ch = e.target.value.replace(/[^0-9]/g, '').slice(-1);
                box.value = ch;
                if (sync() && ch) { setTimeout(() => btn.click(), 120); }
                else if (ch && i < 5) { boxes[i+1].focus(); }
              });

              box.addEventListener('paste', e => {
                e.preventDefault();
                const pasted = (e.clipboardData || window.clipboardData)
                  .getData('text').replace(/[^0-9]/g, '').slice(0, 6);
                pasted.split('').forEach((ch, j) => { if (boxes[i+j]) boxes[i+j].value = ch; });
                boxes[Math.min(i + pasted.length, 5)].focus();
                if (sync()) setTimeout(() => btn.click(), 120);
              });

              box.addEventListener('focus', () => box.select());
            });

            // Copy buttons
            const COPY_SVG  = #{copy_icon_svg.to_json};
            const CHECK_SVG = #{check_icon_svg.to_json};
            document.querySelectorAll('.copy-btn').forEach(btn => {
              btn.addEventListener('click', () => {
                const targetId = btn.dataset.copyTarget;
                const text = document.getElementById(targetId)?.textContent?.trim();
                if (!text) return;
                navigator.clipboard.writeText(text).then(() => {
                  btn.innerHTML = CHECK_SVG;
                  btn.classList.add('copied');
                  setTimeout(() => {
                    btn.innerHTML = COPY_SVG;
                    btn.classList.remove('copied');
                  }, 1800);
                }).catch(() => {
                  // clipboard blocked — select the text as fallback
                  const el = document.getElementById(targetId);
                  if (el) {
                    const range = document.createRange();
                    range.selectNodeContents(el);
                    window.getSelection()?.removeAllRanges();
                    window.getSelection()?.addRange(range);
                  }
                });
              });
            });
          })();
        JS
      end
    end

    # ── Helpers ───────────────────────────────────────────────────────────────

    # rqrcode generates SVGs with explicit width/height but no viewBox.
    # Without viewBox, CSS width/height clips the content rather than scaling it.
    # This injects a viewBox matching the SVG's intrinsic dimensions so CSS
    # can scale the QR code down to fit the card cleanly.
    def scalable_qr_svg
      svg = @qr_svg.dup
      w   = svg[/width="(\d+)"/, 1]&.to_i
      h   = svg[/height="(\d+)"/, 1]&.to_i
      return svg unless w && h
      svg.sub("<svg ", %(<svg viewBox="0 0 #{w} #{h}" ))
    end

    # Groups base32 secret into blocks of 4: "JBSW Y3DP EHPK 3PXP"
    def formatted_secret
      @otp_secret.upcase.gsub(/(.{4})(?=.)/, '\1 ')
    end

    def copy_icon_svg
      '<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="5" width="9" height="9" rx="1.5"/><path d="M3 11V3a1 1 0 0 1 1-1h8"/></svg>'
    end

    def check_icon_svg
      '<svg width="12" height="12" viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="2,8 6,12 14,4"/></svg>'
    end

    def meta_chip(label)
      span(class: "text-[10px] font-medium text-gray-400 bg-white border border-gray-100 " \
                  "rounded-md px-2 py-0.5") do
        plain label
      end
    end
  end
end
