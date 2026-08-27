# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_27_193000) do
  create_table "assets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "portfolio_id", null: false
    t.string "ticker", null: false
    t.datetime "updated_at", null: false
    t.decimal "weight", precision: 8, scale: 6, null: false
    t.index ["portfolio_id", "ticker"], name: "index_assets_on_portfolio_id_and_ticker", unique: true
    t.index ["portfolio_id"], name: "index_assets_on_portfolio_id"
  end

  create_table "historical_prices", force: :cascade do |t|
    t.float "adjusted_close", null: false
    t.integer "asset_id", null: false
    t.float "daily_return"
    t.datetime "traded_at", null: false
    t.integer "volume"
    t.index ["asset_id", "traded_at"], name: "index_historical_prices_on_asset_id_and_traded_at"
    t.index ["asset_id"], name: "index_historical_prices_on_asset_id"
  end

  create_table "portfolios", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.decimal "total_value", precision: 15, scale: 2
    t.datetime "updated_at", null: false
  end

  create_table "stress_test_runs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "elapsed_ms"
    t.string "engine", null: false
    t.text "error_message"
    t.float "expected_shortfall"
    t.json "payload", default: {}
    t.float "sim_expected_max_drawdown"
    t.float "sim_var_30d"
    t.string "status", default: "pending", null: false
    t.integer "stress_test_id", null: false
    t.float "tail_risk_probability"
    t.datetime "updated_at", null: false
    t.float "var_95"
    t.float "var_99"
    t.index ["stress_test_id", "engine"], name: "index_stress_test_runs_on_stress_test_id_and_engine", unique: true
    t.index ["stress_test_id"], name: "index_stress_test_runs_on_stress_test_id"
  end

  create_table "stress_tests", force: :cascade do |t|
    t.json "chart_payload", default: {}
    t.datetime "created_at", null: false
    t.integer "elapsed_ms"
    t.text "error_message"
    t.float "expected_shortfall"
    t.integer "historical_elapsed_ms"
    t.integer "monte_carlo_elapsed_ms"
    t.integer "portfolio_id", null: false
    t.float "sim_expected_max_drawdown"
    t.float "sim_var_30d"
    t.string "status", default: "pending", null: false
    t.float "tail_risk_probability"
    t.datetime "updated_at", null: false
    t.float "var_95"
    t.float "var_99"
    t.integer "wall_elapsed_ms"
    t.index ["portfolio_id", "created_at"], name: "index_stress_tests_on_portfolio_id_and_created_at"
    t.index ["portfolio_id"], name: "index_stress_tests_on_portfolio_id"
  end

  add_foreign_key "assets", "portfolios"
  add_foreign_key "historical_prices", "assets"
  add_foreign_key "stress_test_runs", "stress_tests"
  add_foreign_key "stress_tests", "portfolios"
end
