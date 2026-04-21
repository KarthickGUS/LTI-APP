class CanvasTokenService
  def self.get_access_token(issuer)
    credential = CanvasCredential.find_by(issuer: issuer)
    raise "Missing credential" unless credential

    if credential.expires_at.present? && credential.expires_at > Time.current
      return credential.access_token
    end

    refresh!(credential)
  end

  def self.refresh!(credential)
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
      raise "Re-auth required: #{data['error_description']}"
    end

    credential.update!(
      access_token: data["access_token"],
      refresh_token: data["refresh_token"] || credential.refresh_token,
      expires_at: Time.current + data["expires_in"].to_i.seconds
    )

    data["access_token"]
  end
end
