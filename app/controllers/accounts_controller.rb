require "ims/lti"

class AccountsController < ApplicationController
  skip_before_action :verify_authenticity_token

  def page_views
    begin
      service = CanvasApiService.new

      if params[:user_id].present?
        page_views = service.fetch_user_page_views(params[:user_id])

        data = page_views.map do |pv|
          {
            url: pv["url"],
            interaction_seconds: pv["interaction_seconds"],
            context_type: pv["context_type"],
            visited_at: Time.parse(pv["created_at"])
                            .in_time_zone("Asia/Kolkata")
                            .strftime("%I:%M %p IST")
          }
        end

        render json: data and return
      end

    rescue => e
      Rails.logger.error "Error: #{e.message}"
      render json: { error: "Something went wrong" }, status: 500
    end
  end
end
