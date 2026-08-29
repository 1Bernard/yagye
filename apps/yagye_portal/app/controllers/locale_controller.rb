class LocaleController < ApplicationController
  skip_before_action :authenticate_user!
  skip_after_action :verify_authorized

  def set
    session[:locale] = params[:l].presence_in(%w[en fr]) || "en"
    redirect_back fallback_location: root_path, allow_other_host: false
  end
end
