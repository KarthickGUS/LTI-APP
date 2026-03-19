require "ims/lti"

class LtiController < ApplicationController
  skip_before_action :verify_authenticity_token

  def oidc
    issuer = params[:iss]

    state = SecureRandom.hex(10)
    nonce = SecureRandom.hex(10)

    session[:lti_state] = state
    session[:lti_nonce] = nonce

    auth_url = "http://localhost:3000/api/lti/authorize_redirect"

    query = {
      response_type: "id_token",
      response_mode: "form_post",
      client_id: params[:client_id],
      redirect_uri: params[:target_link_uri],
      login_hint: params[:login_hint],
      lti_message_hint: params[:lti_message_hint],
      nonce: nonce,
      state: state,
      scope: "openid",
      prompt: "none"
    }

    redirect_to "#{auth_url}?#{query.to_query}", allow_other_host: true
  end

  def launch
    Rails.logger.debug "Launch HIT: #{params}"

    if params[:error]
      render plain: "LTI Error: #{params[:error_description]}"
      return
    end

    if params[:state] != session[:lti_state]
      render plain: "Invalid state"
      return
    end

    id_token = params[:id_token]

    if id_token.blank?
      render plain: "Missing id_token"
      return
    end

    begin
      decoded_token = decode_lti_token(id_token)

      Rails.logger.debug "DECODED TOKEN: #{decoded_token}"
      # Example: extract useful data
      user_id = decoded_token["sub"]
      email = decoded_token["email"]
      @user = decoded_token["name"]
      @course = decoded_token.dig("https://purl.imsglobal.org/spec/lti/claim/context", "title")
      @ai_response = "LTI Launched successfully"

      render :launch

    rescue => e
      Rails.logger.error "LTI Decode Error: #{e.message}"
      render plain: "Invalid ID Token ❌"
    end
  end
  private

  def decode_lti_token(id_token)
    unverified = JWT.decode(id_token, nil, false)
    header = unverified[1]

    kid = header["kid"]
    iss = unverified[0]["iss"]

    jwks_url = "#{iss}/api/lti/security/jwks"

    jwks = JSON.parse(Net::HTTP.get(URI(jwks_url)))

    key = jwks["keys"].find { |k| k["kid"] == kid }

    public_key = JWT::JWK.import(key).public_key

    decoded = JWT.decode(
      id_token,
      public_key,
      true,
      {
        algorithm: "RS256",
        iss: iss,
        verify_iss: true,
        aud: params[:client_id],
        verify_aud: true
      }
    )

    decoded.first
  end
end
