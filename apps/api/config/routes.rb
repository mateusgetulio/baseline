Rails.application.routes.draw do
  namespace :v1 do
    get "me", to: "me#show"
    resources :facilities, only: :index do
      resources :courts, only: :index
    end
    get "availability", to: "availability#show"
    resources :holds, only: %i[create destroy] do
      resource :preview, only: :create
    end
    resources :bookings, only: :create
  end

  scope "/sandbox", module: "control" do
    post "/", to: "sandboxes#create"
    scope "/:sandbox_id" do
      post "keys", to: "keys#create"
      delete "keys/:id", to: "keys#destroy"
      post "reset", to: "sandboxes#reset"
      post "holds/:hold_id/expire", to: "holds#expire"
      get "requests", to: "requests#index"
    end
  end

  match "*path", to: "application#route_not_found", via: :all
end
