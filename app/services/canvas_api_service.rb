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


  def fetch_user_page_views(user_id, page = 1)
    response = HTTParty.get(
      "#{@base_url}/api/v1/users/#{user_id}/page_views",
      headers: @headers,
      query: {
        per_page: 10,
        page: page
      }
    )

    raise "Canvas API Error: #{response.code}" unless response.code == 200

    JSON.parse(response.body)
  end

  def extract_links(link_header)
    return {} unless link_header

    links = {}
    link_header.split(",").each do |link|
      url, rel = link.match(/<([^>]+)>;\s*rel="([^"]+)"/).captures
      links[rel.to_sym] = url
    end
    links
  end

  def fetch_course_name(course_id)
    response = HTTParty.get(
      "#{@base_url}/api/v1/courses/#{course_id}",
      headers: @headers
    )

    return nil unless response.code == 200

    JSON.parse(response.body)[0]["name"]
  end
end
