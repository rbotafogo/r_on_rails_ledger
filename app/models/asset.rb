# frozen_string_literal: true

class Asset < ApplicationRecord
  belongs_to :portfolio
  has_many :historical_prices, dependent: :delete_all

  validates :ticker, presence: true, uniqueness: { scope: :portfolio_id }
  validates :weight, presence: true, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }
end
