# frozen_string_literal: true

class StressTest < ApplicationRecord
  belongs_to :portfolio
  has_many :stress_test_runs, dependent: :destroy

  STATUSES = %w[pending calculating completed failed].freeze

  validates :status, inclusion: { in: STATUSES }

  def pending? = status == "pending"
  def calculating? = status == "calculating"
  def completed? = status == "completed"
  def failed? = status == "failed"

  def historical_run
    stress_test_runs.find { |r| r.engine == "historical" }
  end

  def monte_carlo_run
    stress_test_runs.find { |r| r.engine == "monte_carlo" }
  end
end
