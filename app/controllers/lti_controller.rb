require "ims/lti"

class LtiController < ApplicationController
  skip_before_action :verify_authenticity_token

  def oidc
    issuer = params[:iss]

    state = SecureRandom.hex(10)
    nonce = SecureRandom.hex(10)

    session[:lti_state] = state
    session[:lti_nonce] = nonce

    auth_url = "#{issuer}/api/lti/authorize_redirect"

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

  def account_details
    if params[:error]
      return render plain: "LTI Error: #{params[:error_description]}"
    end

    if params[:state] != session[:lti_state]
      return render plain: "Invalid state"
    end

    id_token = params[:id_token]
    return render plain: "Missing id_token" if id_token.blank?

    begin
      decoded_token = decode_lti_token(id_token)

      issuer = decoded_token["iss"]
      session[:current_issuer] = issuer

      account_id = extract_account_id(decoded_token)

      # 🔐 Ensure token exists
      unless valid_canvas_token?(issuer)
        session[:return_to] = request.fullpath
        render_oauth_redirect(issuer)
      end

      load_account_details(issuer)

      rescue => e
        Rails.logger.error "LTI Error: #{e.message}"
        render plain: "Something went wrong ❌"
    end
  end

  def oauth_callback
    issuer = session[:current_issuer]
    code   = params[:code]

    if code.blank?
      unless session[:oauth_attempted]
        session[:oauth_attempted] = true
        return redirect_to canvas_oauth_url(issuer), allow_other_host: true
      else
        return render plain: "OAuth failed or blocked (possible iframe/session issue)"
      end
    end

    response = HTTParty.post(
      "#{issuer}/login/oauth2/token",
      body: {
        grant_type: "authorization_code",
        code: code,
        client_id: client_id_for(issuer),
        client_secret: client_secret_for(issuer),
        redirect_uri: "#{ENV['APP_BASE_URL']}/oauth/callback"
      }
    )

    data = JSON.parse(response.body)

    if data["error"] == "invalid_grant"
      return redirect_to canvas_oauth_url(issuer), allow_other_host: true
    end

    session.delete(:oauth_attempted)

    session[:canvas_tokens] ||= {}

    session[:canvas_tokens][issuer] = {
      access_token: data["access_token"],
      refresh_token: data["refresh_token"],
      expires_at: Time.current + data["expires_in"].to_i.seconds
    }

    load_account_details(issuer)
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

  def extract_account_id(decoded_token)
    return_url = decoded_token["https://purl.imsglobal.org/spec/lti/claim/launch_presentation"]["return_url"]

    account_id = return_url.match(/accounts\/(\d+)/)&.captures&.first
    account_id
  end

  def load_account_details(issuer)
    token = session.dig(:canvas_tokens, issuer, :access_token)
    service = CanvasApiService.new(token, issuer)

    users = service.fetch_users(1)

    @users = users.map do |u|
      {
        id: u["id"],
        name: u["name"]
      }
    end

    render "lti/account_details"
  end

  def render_oauth_redirect(issuer)
      url = canvas_oauth_url(issuer)

      render html: "<script>window.top.location.href='#{url}'</script>".html_safe
  end

  def canvas_oauth_url(issuer)
    redirect_uri = "#{ENV['APP_BASE_URL']}/oauth/callback"

    scopes = [
      "url:GET|/api/v1/accounts/:account_id/users",
      "url:GET|/api/v1/accounts/:account_id/courses"
    ].join(" ")

    oauth_url = "#{issuer}/login/oauth2/auth?" + {
      client_id: client_id_for(issuer),
      response_type: "code",
      redirect_uri: redirect_uri,
      scope: scopes
    }.to_query
  end

  def valid_canvas_token?(issuer)
    token_data = session.dig(:canvas_tokens, issuer)
    return false unless token_data

    token_data = token_data.with_indifferent_access

    access_token = token_data[:access_token]
    refresh_token = token_data[:refresh_token]
    expires_at = token_data[:expires_at]

    return false if access_token.blank?

    if expires_at.present? && Time.parse(expires_at.to_s) < Time.current
      return refresh_canvas_token(issuer)
    end

    true
  end

  def refresh_canvas_token(issuer)
    token_data = session[:canvas_tokens][issuer]

    response = HTTParty.post(
      "#{issuer}/login/oauth2/token",
      body: {
        grant_type: "refresh_token",
        refresh_token: token_data[:refresh_token],
        client_id: client_id_for(issuer),
        client_secret: client_secret_for(issuer)
      }
    )

    data = JSON.parse(response.body)

    if data["error"]
      session[:canvas_tokens].delete(issuer)
      return false
    end

    session[:canvas_tokens][issuer][:access_token] = data["access_token"]
    session[:canvas_tokens][issuer][:refresh_token] = data["refresh_token"] if data["refresh_token"]
    session[:canvas_tokens][issuer][:expires_at] = Time.current + data["expires_in"].to_i.seconds

    true
  end

  def canvas_token
    issuer = session[:current_issuer]
    session.dig(:canvas_tokens, issuer, "access_token")
  end

  def canvas_config(issuer)
    config = CANVAS_APPS[issuer]
    raise "Missing config for #{issuer}" unless config
    config
  end

  def client_id_for(issuer)
    canvas_config(issuer)[:client_id]
  end

  def client_secret_for(issuer)
    canvas_config(issuer)[:client_secret]
  end
end
