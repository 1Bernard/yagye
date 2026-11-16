# frozen_string_literal: true

class CreateAiChatTables < ActiveRecord::Migration[8.0]
  def change
    # ── Threads ──────────────────────────────────────────────────────────────
    # One row per conversation. Title is set from the first user message so the
    # list gives a meaningful label without an extra LLM call.
    create_table :ai_chat_threads, id: :uuid do |t|
      t.references :user,    null: false, foreign_key: true, type: :uuid
      t.text       :context, null: false  # 'merchant' | 'ops'
      t.text       :title                 # auto-set on first user message
      t.datetime   :last_message_at, precision: 6
      t.datetime   :archived_at,     precision: 6
      t.timestamps null: false
    end

    # Primary access pattern: list a user's active threads newest-first,
    # scoped to a context. The partial index excludes archived rows so the
    # planner never visits them.
    add_index :ai_chat_threads,
              %i[user_id context last_message_at],
              order: { last_message_at: :desc },
              where: "archived_at IS NULL",
              name:  "idx_ai_threads_active_user_context"

    # ── Messages ─────────────────────────────────────────────────────────────
    # Append-only: messages are never updated. No updated_at.
    # We load the last 20 for the LLM context window; we display all of them
    # for the history view.
    create_table :ai_chat_messages, id: :uuid do |t|
      t.references :ai_chat_thread, null: false, foreign_key: true, type: :uuid
      t.text       :role,    null: false  # 'user' | 'assistant'
      t.text       :content, null: false
      t.datetime   :created_at, null: false, precision: 6
    end

    # Load all messages for a thread in creation order.
    add_index :ai_chat_messages,
              %i[ai_chat_thread_id created_at],
              name: "idx_ai_messages_thread_order"
  end
end
