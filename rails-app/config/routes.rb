Rails.application.routes.draw do
  namespace :api do
    get "db_info", to: "db_info#show"
    get "db_info_all", to: "db_info#show_all"
  end
end
