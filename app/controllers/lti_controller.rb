require "ims/lti"

class LtiController < ApplicationController
  skip_before_action :verify_authenticity_token

  def oidc
    issuer = params[:iss]

    state = SecureRandom.hex(10)
    nonce = SecureRandom.hex(10)

    session[:lti_state] = state
    session[:lti_nonce] = nonce

    auth_url = "#{ENV["BASE_NGROK_URL"]}/api/lti/authorize_redirect"

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

  # def account_details
  #   # 🔴 Handle LTI errors
  #   if params[:error]
  #     render plain: "LTI Error: #{params[:error_description]}"
  #     return
  #   end

  #   # 🔴 Validate state
  #   if params[:state] != session[:lti_state]
  #     render plain: "Invalid state"
  #     return
  #   end

  #   # 🔴 Decode LTI token
  #   id_token = params[:id_token]
  #   return render plain: "Missing id_token" if id_token.blank?

  #   decoded_token = decode_lti_token(id_token)

  #   # ==============================
  #   # 🔵 STATIC ENV VALUES (HARDCODE)
  #   # ==============================
  #   canvas_url     = "http://localhost:3000"
  #   client_id      = "10000000000003"
  #   client_secret  = "6265f441-b9d2-48f4-bbd3-d462c855b28c"
  #   redirect_uri   = "https://unefficacious-unflatteringly-hailey.ngrok-free.dev/lti/account_details"

  #   # ==============================
  #   # 🟡 STEP 1: If NO code → redirect to OAuth
  #   # ==============================
  #   if params[:code].blank?
  #     oauth_url = "#{canvas_url}/login/oauth2/auth?" +
  #       "client_id=#{client_id}" +
  #       "&response_type=code" +
  #       "&redirect_uri=#{redirect_uri}"
  #     redirect_to oauth_url, allow_other_host: true
  #     return
  #   end

  #   # ==============================
  #   # 🟢 STEP 2: Exchange code → access token
  #   # ==============================
  #   response = HTTParty.post(
  #     "#{canvas_url}/login/oauth2/token",
  #     body: {
  #       grant_type: "authorization_code",
  #       client_id: client_id,
  #       client_secret: client_secret,
  #       redirect_uri: redirect_uri,
  #       code: params[:code]
  #     }
  #   )

  #   body = JSON.parse(response.body)

  #   if body["error"]
  #     render plain: "Token Error: #{body['error_description']}"
  #     return
  #   end

  #   access_token = body["access_token"]

  #   # ==============================
  #   # 🟢 STEP 3: Call Canvas API
  #   # ==============================
  #   courses_response = HTTParty.get(
  #     "#{canvas_url}/api/v1/users/self/courses",
  #     headers: {
  #       "Authorization" => "Bearer #{access_token}"
  #     }
  #   )

  #   @courses = JSON.parse(courses_response.body)

  #   # ==============================
  #   # 🟢 STEP 4: Render View
  #   # ==============================
  #   render :courses
  # end
  #
  #

  def account_details
    if params[:error]
      render plain: "LTI Error: #{params[:error_description]}"
      return
    end

    if params[:state] != session[:lti_state]
      render plain: "Invalid state"
      return
    end

    id_token = params[:id_token]
    return render plain: "Missing id_token" if id_token.blank?

    begin
      decoded_token = decode_lti_token(id_token)

      account_id = extract_account_id(decoded_token)

      service = CanvasApiService.new
      users   = service.fetch_users(account_id)

      @users = users.map do |u|
        {
          id: u["id"],
          name: u["name"]
        }
      end

    rescue => e
      Rails.logger.error "LTI Error: #{e.message}"
      render plain: "Something went wrong ❌"
    end
  end

private

  def get_canvas_access_token(decoded_token)
    token_url = "http://localhost:3000/login/oauth2/token"

    response = HTTParty.post(token_url, body: {
      grant_type: "client_credentials",
      client_assertion_type: "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
      client_assertion: generate_client_assertion(decoded_token),
      scope: [
          "https://purl.imsglobal.org/spec/lti-ags/scope/lineitem",
          "https://purl.imsglobal.org/spec/lti-ags/scope/result.readonly",
          "https://purl.imsglobal.org/spec/lti-nrps/scope/contextmembership.readonly"
        ].join(" ")
    })
    JSON.parse(response.body)["access_token"]
  end


  def get_courses(access_token)
    HTTParty.get(
      "http://localhost:3000/api/v1/users/self/courses",
      headers: {
        "Cookie" => request.headers["Cookie"]
      }
    )
  end

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

  def generate_client_assertion(decoded_token)
    client_id = decoded_token["aud"]
    payload = {
      iss: client_id,
      sub: client_id,
      aud: "http://localhost:3000/login/oauth2/token",
      iat: Time.now.to_i,
      exp: Time.now.to_i + 300,
      jti: SecureRandom.uuid
    }

    private_key = OpenSSL::PKey::RSA.new(File.read("config/keys/private.key"))

    JWT.encode(payload, private_key, "RS256", kid: "ai-assistant-key")
  end

  def extract_account_id(decoded_token)
    return_url = decoded_token["https://purl.imsglobal.org/spec/lti/claim/launch_presentation"]["return_url"]

    account_id = return_url.match(/accounts\/(\d+)/)&.captures&.first
    account_id
  end
end
