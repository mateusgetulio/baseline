Rails.application.routes.draw do
  namespace :v1 do
    get "me", to: "me#show"
    resources :facilities, only: :index do
      resources :courts, only: :index
    end
    get "availability", to: "availability#show"
    resources :holds, only: %i[create destroy]
  end

  match "*path", to: "application#route_not_found", via: :all
end
