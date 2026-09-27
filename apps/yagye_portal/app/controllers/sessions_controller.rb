# frozen_string_literal: true

class SessionsController < ApplicationController
  skip_after_action :verify_authorized

  def keepalive
    render json: { ok: true }, status: :ok
  end
end
