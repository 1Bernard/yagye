# frozen_string_literal: true

module Ai
  # Shared persistence layer for both merchant and ops AI chat controllers.
  # Including controllers must define `chat_context` returning one of
  # AiChatThread::CONTEXTS.
  module ChatHistory
    extend ActiveSupport::Concern

    # GET  /ai/chat/threads
    # GET  /ai/ops-chat/threads
    def threads
      skip_authorization
      rows = user_threads.active.in_context(chat_context).recent
      render json: { threads: rows.map { serialize_thread(_1) } }
    end

    # GET  /ai/chat/threads/:thread_id
    # GET  /ai/ops-chat/threads/:thread_id
    def messages
      skip_authorization
      thread = find_thread!(params[:thread_id])
      msgs   = thread.ai_chat_messages.map { { role: _1.role, content: _1.content } }
      render json: { thread: serialize_thread(thread), messages: msgs }
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Thread not found" }, status: :not_found
    end

    # DELETE /ai/chat/threads/:thread_id
    # DELETE /ai/ops-chat/threads/:thread_id
    def destroy_thread
      skip_authorization
      thread = find_thread!(params[:thread_id])
      thread.update!(archived_at: Time.current)
      render json: { ok: true }
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Thread not found" }, status: :not_found
    end

    private

    def find_or_create_thread(thread_id)
      if thread_id.present?
        user_threads.active.in_context(chat_context).find_by(id: thread_id) ||
          build_thread
      else
        build_thread
      end
    end

    def build_thread
      AiChatThread.create!(user: current_user, context: chat_context,
                            last_message_at: Time.current)
    end

    def find_thread!(id)
      user_threads.in_context(chat_context).find(id)
    end

    def user_threads
      AiChatThread.for_user(current_user)
    end

    def persist_exchange(thread:, user_message:, assistant_reply:)
      thread.ai_chat_messages.create!(role: "user",      content: user_message)
      thread.ai_chat_messages.create!(role: "assistant", content: assistant_reply)
      thread.update!(
        last_message_at: Time.current,
        title:           thread.title.presence || AiChatThread.title_from(user_message)
      )
    end

    def serialize_thread(t)
      {
        id:              t.id,
        title:           t.title_or_default,
        last_message_at: t.last_message_at&.iso8601
      }
    end
  end
end
