class PageViewsController < ApplicationController
  skip_before_action :verify_authenticity_token

  def start
    user_id = params[:user_id]

    start_date = Date.today.prev_month.beginning_of_month.to_s
    end_date   = Date.today.beginning_of_month.to_s

    response = HTTParty.post(
      "#{ENV['CANVAS_BASE_URL']}/api/v1/users/#{user_id}/page_views/query",
      headers: {
        "Authorization" => "Bearer #{ENV['CANVAS_API_TOKEN']}"
      },
      body: {
        start_date: start_date,
        end_date: end_date,
        results_format: "csv"
      }
    )

    if response.code != 201
      render json: { error: response.body }, status: :bad_request
      return
    end

    poll_url = response["poll_url"]
    query_id = poll_url.split("/").last

    render json: { query_id: query_id }
  end

  def status
    user_id  = params[:user_id]
    query_id = params[:query_id]

    response = HTTParty.get(
      "#{ENV['CANVAS_BASE_URL']}/api/v1/users/#{user_id}/page_views/query/#{query_id}/results",
      headers: {
        "Authorization" => "Bearer #{ENV['CANVAS_API_TOKEN']}"
      }
    )

    render json: response.parsed_response
  end

  def download
    user_id  = params[:user_id]
    query_id = params[:query_id]

    response = HTTParty.get(
      "#{ENV['CANVAS_BASE_URL']}/api/v1/users/#{user_id}/page_views/query/#{query_id}/results",
      headers: {
        "Authorization" => "Bearer #{ENV['CANVAS_API_TOKEN']}"
      }
    )

    send_data response.body,
              filename: "page_views_#{query_id}.csv",
              type: "text/csv"
  end
end
