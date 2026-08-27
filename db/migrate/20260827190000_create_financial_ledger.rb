class CreateFinancialLedger < ActiveRecord::Migration[8.1]
  def change
    create_table :portfolios do |t|
      t.string :name, null: false
      t.decimal :total_value, precision: 15, scale: 2
      t.timestamps
    end

    create_table :assets do |t|
      t.references :portfolio, null: false, foreign_key: true
      t.string :ticker, null: false
      t.decimal :weight, precision: 8, scale: 6, null: false
      t.timestamps
    end
    add_index :assets, [:portfolio_id, :ticker], unique: true

    create_table :historical_prices do |t|
      t.references :asset, null: false, foreign_key: true
      t.datetime :traded_at, null: false
      t.float :adjusted_close, null: false
      t.float :daily_return
      t.integer :volume
    end
    add_index :historical_prices, [:asset_id, :traded_at]

    create_table :stress_tests do |t|
      t.references :portfolio, null: false, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.float :var_95
      t.float :var_99
      t.float :expected_shortfall
      t.integer :elapsed_ms
      t.text :error_message
      t.json :chart_payload, default: {}
      t.timestamps
    end
    add_index :stress_tests, [:portfolio_id, :created_at]
  end
end
