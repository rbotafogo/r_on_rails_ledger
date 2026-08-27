# frozen_string_literal: true

class StressTestRun < ApplicationRecord
  belongs_to :stress_test

  ENGINES = %w[historical monte_carlo].freeze
  STATUSES = %w[pending calculating completed failed].freeze

  validates :engine, inclusion: { in: ENGINES }
  validates :status, inclusion: { in: STATUSES }

  def historical? = engine == "historical"
  def monte_carlo? = engine == "monte_carlo"
  def completed? = status == "completed"
  def failed? = status == "failed"
end
