class RefreshCanvasTokensJob < ApplicationJob
  queue_as :default

  def perform
    CanvasCredential.expiring_soon.find_each do |credential|
      begin
        refresh_token(credential)
      rescue => e
        Rails.logger.error "Token refresh failed for #{credential.issuer}: #{e.message}"
      end
    end
  end

  private

  def refresh_token(credential)
    response = HTTParty.post(
      "#{credential.issuer}/login/oauth2/token",
      body: {
        grant_type: "refresh_token",
        refresh_token: credential.refresh_token,
        client_id: credential.client_id,
        client_secret: credential.client_secret
      }
    )

    data = JSON.parse(response.body)

    if data["error"]
      Rails.logger.error "Re-auth required for #{credential.issuer}"
      return
    end

    credential.update!(
      access_token: data["access_token"],
      refresh_token: data["refresh_token"] || credential.refresh_token,
      expires_at: Time.current + data["expires_in"].to_i.seconds
    )

    Rails.logger.info "Token refreshed for #{credential.issuer}"
  end
end
