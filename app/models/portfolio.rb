# frozen_string_literal: true

class Portfolio < ApplicationRecord
  has_many :assets, dependent: :destroy
  has_many :historical_prices, through: :assets
  has_many :stress_tests, dependent: :destroy

  validates :name, presence: true
end
