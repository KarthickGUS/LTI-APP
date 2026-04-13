Rails.application.configure do
  config.cache_classes = true
  config.eager_load = true

  config.log_level = :debug

  config.hosts.clear

  config.consider_all_requests_local = true

  ENV["CANVAS_API_TOKEN"] = "2nm9Xxm4PVyY43BUntTvC2ZcUhM2U8nKaM3EGve77uYwDcw94wYW8LXYJcMvAeYB"
  ENV["CANVAS_BASE_URL"] = "http://localhost:3000/"
end
