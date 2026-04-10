Rails.application.routes.draw do
  scope :lti do
    post "launch", to: "lti#launch"
    post "oidc",   to: "lti#oidc"
    post "account_details", to: "lti#account_details"
  end

  scope :accounts do
    get "/page_views", to: "accounts#page_views"
    get "/assignment_analytics", to: "accounts#assignment_analytics"
    get "/courses", to: "accounts#courses"
    get "/user_activity", to: "accounts#user_activity"
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check
  get "export_course", to: "exports#export_course"
  get "export_course_ids", to: "exports#export_course_ids"
  get "convert_json_to_excel", to: "exports#convert_json_to_excel"


  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
