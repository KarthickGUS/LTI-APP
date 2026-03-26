class CanvasApiService
  include HTTParty

  def initialize
    @base_url = ENV["CANVAS_BASE_URL"]
    @token    = ENV["CANVAS_API_TOKEN"]
    @headers  = {
      "Authorization" => "Bearer #{@token}"
    }
  end

  def fetch_users(account_id)
    response = HTTParty.get(
      "#{@base_url}/api/v1/accounts/#{account_id}/users",
      headers: @headers
    )

    raise "Canvas API Error: #{response.body}" unless response.code == 200

    JSON.parse(response.body)
  end

  def fetch_user_page_views(user_id)
    response = HTTParty.get(
      "#{@base_url}/api/v1/users/#{user_id}/page_views",
      headers: @headers,
      query: {
        per_page: 50
      }
    )

    unless response.code == 200
      raise "Canvas API Error: #{response.code} - #{response.body}"
    end

    JSON.parse(response.body)
  end
end
