Rails.application.configure do
  # Code loading
  config.cache_classes = true
  config.eager_load = true

  config.consider_all_requests_local = true

  config.log_level = :debug

  config.hosts.clear

  config.session_store :cookie_store, key: "_lti_app_session"

  config.force_ssl = false
end
