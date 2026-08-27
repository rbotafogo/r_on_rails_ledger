# frozen_string_literal: true

class HistoricalPrice < ApplicationRecord
  belongs_to :asset

  validates :traded_at, :adjusted_close, presence: true
end
