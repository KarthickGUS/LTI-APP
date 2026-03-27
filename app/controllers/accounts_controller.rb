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
        created_at: Time.parse(pv["created_at"])
                        .in_time_zone("Asia/Kolkata")
                        .strftime("%d %b %Y, %I:%M %p IST"),
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
      has_next: data.length == 10,  # simple check
      has_prev: page > 1
    }
  end

  def grade_history
    return render json: [] if params[:user_id].blank?

    course_id = params[:course_id]

    service = CanvasApiService.new
    history = service.fetch_grade_history(course_id)

    user_history = history.select { |h| h["user_id"].to_s == params[:user_id].to_s }

    data = user_history.map do |h|
      {
        assignment_name: h["assignment_name"],
        course_name: "Course #{course_id}", # or fetch real name if needed
        score: h["score"],
        grade: h["grade"],
        grader: h["grader"],
        graded_at: Time.parse(h["graded_at"])
                        .in_time_zone("Asia/Kolkata")
                        .strftime("%d %b %Y, %I:%M %p IST")
      }
    end

    render json: data
  end
end
