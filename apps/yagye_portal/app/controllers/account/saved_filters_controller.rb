# frozen_string_literal: true

module Account
  class SavedFiltersController < ApplicationController
    # POST /settings/saved-filters
    # Called from filter drawers (payments, settlements, etc.) via data-turbo-frame="_top"
    # so the whole page navigates, not just the drawer frame.
    def create
      authorize :settings, :update?

      @filter = SavedFilter.new(saved_filter_params.merge(user: current_user))

      if @filter.save
        redirect_back_or_to root_path, notice: "Filter "# {@filter.name}" saved."
      else
        redirect_back_or_to root_path,
                            alert: @filter.errors.full_messages.to_sentence
      end
    end

    # DELETE /settings/saved-filters/:id
    def destroy
      authorize :settings, :update?

      filter = current_user.saved_filters.find(params[:id])
      filter.destroy!

      redirect_back_or_to root_path, notice: "Filter removed."
    end

    private

    def saved_filter_params
      params.require(:saved_filter).permit(:namespace, :name, :shared_with_merchant, filters: {})
    end
  end
end
