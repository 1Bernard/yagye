# frozen_string_literal: true

module Settings
  class TotpRecoveryCodesView < ApplicationComponent
    include UI::Theme

    def initialize(current_user:, recovery_codes:)
      @current_user   = current_user
      @recovery_codes = recovery_codes
    end

    def view_template
      # Full-screen, distraction-free — no sidebar or topbar (GitHub / Stripe / 1Password pattern)
      content_for(:body_class) { "bg-gray-50" }
      style { raw safe("html,body{margin:0;padding:0}") }
      recovery_styles
      div(class: "min-h-screen flex flex-col") do
        minimal_header
        main_content
      end
      recovery_script
      render UI::Flash.new(flash: flash)
    end

    private

    # ── Styles ────────────────────────────────────────────────────────────────

    def recovery_styles
      style do
        raw safe(<<~CSS)
          .code-pill {
            display: flex; align-items: center; gap: 8px;
            padding: 11px 14px; border-radius: 10px;
            background: #f9fafb; border: 1px solid #f3f4f6;
            cursor: pointer; transition: background .12s, border-color .12s;
            user-select: none;
          }
          .code-pill:hover { background: #f0f4ff; border-color: #c7d2fe; }
          .code-pill.copied { background: #f0fdf4; border-color: #bbf7d0; }
          .code-pill.copied .pill-code { color: #16a34a; }
          .pill-code {
            font-family: ui-monospace, 'Cascadia Code', monospace;
            font-size: 13.5px; font-weight: 700;
            letter-spacing: .08em; color: #1f2937; flex: 1;
          }
          .pill-icon { width: 13px; height: 13px; flex-shrink: 0; color: #d1d5db; transition: color .12s; }
          .code-pill:hover   .pill-icon { color: #6366f1; }
          .code-pill.copied  .pill-icon { color: #16a34a; }

          #done-btn { transition: opacity .2s, background .2s; }
          #done-btn:disabled { opacity: .38; cursor: not-allowed; }

          #copy-all-btn.copied { color: #16a34a; border-color: #bbf7d0; background: #f0fdf4; }
        CSS
      end
    end

    # ── Minimal header ────────────────────────────────────────────────────────

    def minimal_header
      div(class: "shrink-0 flex items-center justify-between px-8 py-5 border-b border-gray-100 bg-white") do
        img(src: asset_path("yagye-text.png"), alt: "Yagye", class: "h-7 w-auto")
        span(class: "text-[11px] font-semibold uppercase tracking-[0.18em] text-gray-400") do
          plain "Recovery codes"
        end
      end
    end

    # ── Main content ──────────────────────────────────────────────────────────

    def main_content
      div(class: "flex-1 flex flex-col items-center justify-center px-4 py-12") do
        div(class: "w-full max-w-[520px] flex flex-col gap-5") do
          warning_section
          action_buttons
          codes_grid
          acknowledgment_row
          done_button
        end
      end
    end

    def warning_section
      div(class: "rounded-2xl px-5 py-5 flex items-start gap-4",
          style: "background:rgba(245,158,11,0.07);border:1.5px solid rgba(245,158,11,0.25)") do
        div(class: "flex w-10 h-10 rounded-xl items-center justify-center flex-shrink-0 mt-0.5",
            style: "background:rgba(245,158,11,0.12)") do
          span(class: "flex w-5 h-5", style: "color:#d97706") do
            render UI::Icon.new(:alert_triangle, class: "w-full h-full")
          end
        end
        div do
          p(class: "text-[14px] font-bold text-amber-900 mb-1") do
            plain "Save these codes — you won't see them again"
          end
          p(class: "text-[12.5px] leading-relaxed text-amber-800") do
            plain "Each code can be used once to regain access if you lose your authenticator app. " \
                  "Store them in a password manager or print them and keep them somewhere safe."
          end
        end
      end
    end

    def action_buttons
      div(class: "flex items-center gap-2.5") do
        # Download as .txt
        button(
          type: "button", id: "download-btn",
          class: "inline-flex items-center gap-2 px-4 py-[9px] rounded-xl border border-gray-200 " \
                 "text-[12.5px] font-semibold text-gray-600 bg-white hover:bg-gray-50 transition-colors"
        ) do
          span(class: "flex w-[13px] h-[13px]") { render UI::Icon.new(:download, class: "w-full h-full") }
          plain "Download .txt"
        end

        # Copy all
        button(
          type: "button", id: "copy-all-btn",
          class: "inline-flex items-center gap-2 px-4 py-[9px] rounded-xl border border-gray-200 " \
                 "text-[12.5px] font-semibold text-gray-600 bg-white hover:bg-gray-50 transition-colors"
        ) do
          span(class: "flex w-[13px] h-[13px]") { render UI::Icon.new(:copy, class: "w-full h-full") }
          span(id: "copy-all-label") { plain "Copy all" }
        end
      end
    end

    def codes_grid
      div(class: "bg-white rounded-2xl border border-gray-100 overflow-hidden") do
        div(class: "grid grid-cols-2 gap-2.5 p-5") do
          @recovery_codes.each_with_index do |code, i|
            button(
              type: "button",
              class: "code-pill",
              title: "Click to copy",
              data: { code: code, idx: i }
            ) do
              span(class: "pill-code") { plain code }
              span(class: "pill-icon") do
                raw safe('<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="5" width="9" height="9" rx="1.5"/><path d="M3 11V3a1 1 0 0 1 1-1h8"/></svg>')
              end
            end
          end
        end
        div(class: "px-5 py-3 border-t border-gray-50 flex items-center gap-1.5") do
          span(class: "flex w-3 h-3 text-gray-300") { render UI::Icon.new(:info_circle, class: "w-full h-full") }
          p(class: "text-[11px] text-gray-400") do
            plain "Click any code to copy it individually. Each code can only be used once."
          end
        end
      end
    end

    def acknowledgment_row
      label(class: "flex items-start gap-3 cursor-pointer group") do
        input(
          type: "checkbox", id: "confirm-saved",
          class: "mt-[2px] h-4 w-4 rounded border-gray-300 flex-shrink-0 cursor-pointer",
          style: "accent-color:#3D47F5"
        )
        span(class: "text-[13px] text-gray-600 leading-snug group-hover:text-gray-800 transition-colors") do
          plain "I have saved these recovery codes in a secure location (password manager, printed copy, or encrypted file)."
        end
      end
    end

    def done_button
      a(
        href: root_path,
        id: "done-btn",
        class: "w-full inline-flex items-center justify-center gap-2 rounded-xl px-4 py-3.5 " \
               "text-[13.5px] font-semibold text-white no-underline pointer-events-none",
        style: "background:#3D47F5;opacity:.38",
        aria: { disabled: "true" }
      ) do
        span(class: "flex w-[15px] h-[15px]") { render UI::Icon.new(:check_circle, class: "w-full h-full") }
        plain "I've saved my codes — take me to my dashboard"
      end
    end

    # ── Inline JS ─────────────────────────────────────────────────────────────

    def recovery_script
      codes_json = @recovery_codes.to_json
      email      = @current_user.email.to_s

      script(nonce: content_security_policy_nonce) do
        raw safe(<<~JS)
          (function () {
            const CODES   = #{codes_json};
            const EMAIL   = #{email.to_json};
            const CHECK_SVG = '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><polyline points="2,8 6,12 14,4"/></svg>';
            const COPY_SVG  = '<svg viewBox="0 0 16 16" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="5" width="9" height="9" rx="1.5"/><path d="M3 11V3a1 1 0 0 1 1-1h8"/></svg>';

            // ── Individual code copy ────────────────────────────────────────
            document.querySelectorAll('.code-pill').forEach(pill => {
              pill.addEventListener('click', () => {
                const code = pill.dataset.code;
                navigator.clipboard.writeText(code).then(() => {
                  pill.classList.add('copied');
                  pill.querySelector('.pill-icon').innerHTML = CHECK_SVG;
                  setTimeout(() => {
                    pill.classList.remove('copied');
                    pill.querySelector('.pill-icon').innerHTML = COPY_SVG;
                  }, 2000);
                }).catch(() => {
                  const range = document.createRange();
                  range.selectNodeContents(pill.querySelector('.pill-code'));
                  window.getSelection()?.removeAllRanges();
                  window.getSelection()?.addRange(range);
                });
              });
            });

            // ── Copy all ───────────────────────────────────────────────────
            const copyAllBtn   = document.getElementById('copy-all-btn');
            const copyAllLabel = document.getElementById('copy-all-label');
            copyAllBtn?.addEventListener('click', () => {
              navigator.clipboard.writeText(CODES.join('\\n')).then(() => {
                copyAllBtn.classList.add('copied');
                copyAllLabel.textContent = 'Copied!';
                setTimeout(() => {
                  copyAllBtn.classList.remove('copied');
                  copyAllLabel.textContent = 'Copy all';
                }, 2000);
              });
            });

            // ── Download .txt ──────────────────────────────────────────────
            document.getElementById('download-btn')?.addEventListener('click', () => {
              const content = [
                'Yagye Recovery Codes',
                'Account: ' + EMAIL,
                'Generated: ' + new Date().toISOString().slice(0, 10),
                '',
                'Keep these codes safe. Each can be used once.',
                '',
                ...CODES.map((c, i) => (i + 1) + '. ' + c)
              ].join('\\n');
              const a = document.createElement('a');
              a.href     = 'data:text/plain;charset=utf-8,' + encodeURIComponent(content);
              a.download = 'yagye-recovery-codes.txt';
              a.click();
            });

            // ── Checkbox gate ──────────────────────────────────────────────
            const checkbox = document.getElementById('confirm-saved');
            const doneBtn  = document.getElementById('done-btn');
            checkbox?.addEventListener('change', () => {
              if (checkbox.checked) {
                doneBtn.style.opacity     = '1';
                doneBtn.style.pointerEvents = '';
                doneBtn.removeAttribute('aria-disabled');
              } else {
                doneBtn.style.opacity     = '.38';
                doneBtn.style.pointerEvents = 'none';
                doneBtn.setAttribute('aria-disabled', 'true');
              }
            });
          })();
        JS
      end
    end
  end
end
