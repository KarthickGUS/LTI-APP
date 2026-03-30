require "ims/lti"

class AccountsController < ApplicationController
  skip_before_action :verify_authenticity_token

  def page_views
    return render json: [] if params[:user_id].blank?

    page = params[:page].to_i
    page = 1 if page <= 0

    service = CanvasApiService.new
    page_views = service.fetch_user_page_views(params[:user_id], page)

    data = page_views.map do |pv|
      course_name = nil

      if pv["context_type"] == "Course" && pv["links"] && pv["links"]["context"]
        course_name = service.fetch_course_name(pv["context_id"])
      end

      {
        url: pv["url"],
        course_name: course_name,
        context_type: pv["context_type"],
        controller: pv["controller"],
        action: pv["action"],
        interaction_seconds: pv["interaction_seconds"],
        created_at: pv["created_at"],
        participated: pv["participated"],
        contributed: pv["contributed"],
        summarized: pv["summarized"],
        asset_user_access_id: pv["asset_user_access_id"],
        app_name: pv["app_name"],
        user_request: pv["user_request"],
        render_time: pv["render_time"]
      }
    end

    render json: {
      data: data,
      current_page: page,
      has_next: data.length == 10,
      has_prev: page > 1
    }
  end

  def assignment_analytics
    course_id = params[:course_id]
    user_id = params[:user_id]

    response = HTTParty.get(
      "#{ENV['CANVAS_BASE_URL']}/api/v1/courses/#{course_id}/analytics/users/#{user_id}/assignments",
      headers: {
        "Authorization" => "Bearer #{ENV['CANVAS_API_TOKEN']}"
      }
    )

    render json: JSON.parse(response.body)
  end

  def courses
    account_id = params[:user_id]

    response = HTTParty.get(
      "#{ENV['CANVAS_BASE_URL']}/api/v1/accounts/#{account_id}/courses",
      headers: {
        "Authorization" => "Bearer #{ENV['CANVAS_API_TOKEN']}"
      }
    )

    render json: JSON.parse(response.body)
  end
end
