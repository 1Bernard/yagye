# frozen_string_literal: true

module Compliance
  class KybReviewsController < ApplicationController
    def index
      authorize :kyb_reviews, :index?
      tab          = params[:tab].presence_in(%w[pending in_review approved rejected]) || "pending"
      applications = Compliance::ApplicationsQuery.new.call(tab: tab)
      render KybReviews::IndexView.new(tab: tab, applications: applications)
    end

    def show
      authorize :kyb_reviews, :show?
      @application = PortalMerchantApplication.find(params[:id])
    end
  end
end
