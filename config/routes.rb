Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  resources :docs, only: %i[index show]

  resources :portfolios, only: %i[index show] do
    resources :stress_tests, only: %i[create]
  end

  root "portfolios#index"
end
