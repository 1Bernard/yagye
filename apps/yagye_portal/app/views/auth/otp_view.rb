# frozen_string_literal: true

module Auth
  class OtpView < ApplicationComponent
    include UI::Theme

    def initialize(csrf_token:, via_email: false, user_email: nil)
      @csrf_token = csrf_token
      @via_email  = via_email
      @user_email = user_email
    end

    def view_template
      title    = @via_email ? "Check your email"               : "Two-step verification"
      subtitle = @via_email ? "Enter the 6-digit code we sent you." \
                            : "Enter the 6-digit code from your authenticator app."

      render Auth::Shell.new(title: title, subtitle: subtitle) do
        otp_styles
        otp_content
        otp_script
      end
    end

    private

    def masked_email
      return nil unless @user_email
      local, domain = @user_email.split("@")
      return @user_email unless domain
      masked = if local.length <= 2
                 local
               elsif local.length == 3
                 "#{local[0]}*#{local[-1]}"
               else
                 "#{local[0]}#{"*" * [local.length - 2, 4].min}#{local[-1]}"
               end
      "#{masked}@#{domain}"
    end

    # ── Styles ────────────────────────────────────────────────────────────────

    def otp_styles
      style do
        raw safe(<<~CSS)
          .otp-box {
            width: 48px; height: 56px;
            border: 1.5px solid #e5e7eb;
            border-radius: 12px;
            font-size: 26px; font-weight: 700;
            text-align: center; color: #111827;
            background: #f9fafb;
            transition: border-color .15s, box-shadow .15s, background .15s;
            outline: none; caret-color: transparent;
            -webkit-appearance: none;
          }
          .otp-box:focus {
            border-color: #3D47F5; background: #fff;
            box-shadow: 0 0 0 3px rgba(61,71,245,0.12);
          }
          .otp-box.otp-filled { border-color: #3D47F5; background: #fff; }
          .otp-box.otp-error  {
            border-color: #ef4444; background: #fef2f2;
            animation: otp-shake 0.35s ease;
          }
          @keyframes otp-shake {
            0%,100% { transform: translateX(0); }
            20%,60% { transform: translateX(-5px); }
            40%,80% { transform: translateX(5px); }
          }
          #otp-submit { transition: opacity .2s; }
          #otp-submit:disabled { opacity: .38; cursor: not-allowed; }

          .otp-or-divider {
            display: flex; align-items: center; gap: 12px; margin: 18px 0 14px;
          }
          .otp-or-divider::before,
          .otp-or-divider::after {
            content: ""; flex: 1; height: 1px; background: #f3f4f6;
          }
          .otp-or-divider span {
            font-size: 11px; font-weight: 500; color: #d1d5db;
            text-transform: uppercase; letter-spacing: .08em;
          }

          .otp-alt-btn {
            display: inline-flex; align-items: center; justify-content: center; gap: 7px;
            width: 100%; padding: 11px 16px; border-radius: 12px;
            border: 1.5px solid #e5e7eb; background: #fff;
            font-size: 13px; font-weight: 500; color: #374151;
            cursor: pointer; transition: border-color .15s, background .15s, color .15s;
            text-decoration: none;
          }
          .otp-alt-btn:hover {
            border-color: #c7d2fe; background: #f5f7ff; color: #3D47F5;
          }
          .otp-alt-btn .btn-icon { flex-shrink: 0; width: 14px; height: 14px; }

          #resend-countdown { color: #9ca3af; font-size: 12.5px; }
          #resend-btn { display: none; }
        CSS
      end
    end

    # ── Main content ──────────────────────────────────────────────────────────

    def otp_content
      form(action: users_verify_otp_path, method: :post, id: "otp-form") do
        input(type: "hidden", name: :authenticity_token, value: @csrf_token)
        input(type: "hidden", name: "user[otp_attempt]", id: "otp-hidden", value: "")

        div(class: "flex justify-center gap-2 mb-2") do
          6.times do |i|
            input(
              type:         "text",
              maxlength:    "1",
              inputmode:    "numeric",
              pattern:      "[0-9]",
              autocomplete: i.zero? ? "one-time-code" : "off",
              autofocus:    i.zero?,
              class:        "otp-box",
              data:         { otp_idx: i.to_s }
            )
          end
        end

        # Caption beneath the boxes
        div(class: "text-center mb-6 mt-2") do
          if @via_email && @user_email
            p(class: "text-[12.5px] text-gray-500 mb-0.5") do
              plain "Sent to "
              span(class: "font-semibold text-gray-700") { plain masked_email }
            end
            p(class: "text-[11.5px] text-gray-400") { plain "Valid for 10 minutes" }
          else
            p(class: "text-[11.5px] text-gray-400") do
              plain "Google Authenticator · Authy · 1Password"
            end
          end
        end

        button(
          type:     :submit,
          id:       "otp-submit",
          disabled: true,
          class:    "w-full inline-flex items-center justify-center rounded-xl px-4 py-3.5 " \
                    "text-sm font-semibold text-white shadow-lg",
          style:    "background-color:#3D47F5",
          data: {
            controller:                        "loading-button",
            action:                            "click->loading-button#start",
            loading_button_loading_text_value: "Verifying…"
          }
        ) do
          render UI::Icon.new(:spinner, class: "w-4 h-4 mr-2 animate-spin hidden",
                                        data: { loading_button_target: "spinner" })
          span(data: { loading_button_target: "label" }) { plain "Verify" }
        end
      end

      # ── Secondary actions ─────────────────────────────────────────────────
      div(class: "otp-or-divider") { span { plain "or" } }

      if @via_email
        email_resend_button
      else
        email_fallback_button
      end

      div(class: "mt-4 text-center") do
        a(href: new_user_session_path,
          class: "text-[11.5px] text-gray-400 hover:text-gray-500 transition-colors") do
          plain "Use a different account"
        end
      end

      totp_upgrade_nudge if @via_email
    end

    # ── Secondary action buttons ──────────────────────────────────────────────

    # Email path: resend inline as outlined button
    def email_resend_button
      div(class: "flex items-center justify-center gap-1.5") do
        span(class: "text-[12.5px] text-gray-400") { plain "Didn't receive it?" }
        span(id: "resend-countdown") { plain " Resend in 60s" }
        form(action: users_request_email_otp_path, method: :post, id: "resend-form", class: "inline") do
          input(type: "hidden", name: :authenticity_token, value: @csrf_token)
          button(type: :submit, id: "resend-btn",
                 class: "text-[12.5px] font-semibold bg-transparent border-0 cursor-pointer p-0",
                 style: "color:#3D47F5") do
            plain "Resend"
          end
        end
      end
    end

    # TOTP path: "send email code instead" as a real outlined button
    def email_fallback_button
      form(action: users_request_email_otp_path, method: :post) do
        input(type: "hidden", name: :authenticity_token, value: @csrf_token)
        button(type: :submit, class: "otp-alt-btn") do
          span(class: "btn-icon") { render UI::Icon.new(:mail, class: "w-full h-full") }
          plain "Send a code to my email instead"
        end
      end
    end

    def totp_upgrade_nudge
      div(class: "mt-5 rounded-xl border border-blue-100 px-4 py-3",
          style: "background:#eff6ff") do
        div(class: "flex items-start gap-2.5") do
          span(class: "flex w-4 h-4 text-blue-400 flex-shrink-0 mt-0.5") do
            render UI::Icon.new(:shield, class: "w-full h-full")
          end
          p(class: "text-[12px] leading-snug", style: "color:#1d4ed8") do
            plain "Tip: Set up an authenticator app for faster, offline codes — more reliable than email."
          end
        end
      end
    end

    # ── Inline JS ─────────────────────────────────────────────────────────────

    def otp_script
      script do
        raw safe(<<~JS)
          (function () {
            const boxes  = [...document.querySelectorAll('.otp-box')];
            const hidden = document.getElementById('otp-hidden');
            const btn    = document.getElementById('otp-submit');

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

            // Email resend countdown
            const cdEl      = document.getElementById('resend-countdown');
            const resendBtn = document.getElementById('resend-btn');
            if (cdEl && resendBtn) {
              let secs = 60;
              const interval = setInterval(() => {
                secs--;
                if (secs <= 0) {
                  clearInterval(interval);
                  cdEl.style.display      = 'none';
                  resendBtn.style.display = 'inline';
                } else {
                  cdEl.textContent = ' Resend in ' + secs + 's';
                }
              }, 1000);
            }
          })();
        JS
      end
    end
  end
end
