Rails.application.config.session_store :cookie_store,
  key: "_lti_external_app_session",
  same_site: :none,
  secure: true
