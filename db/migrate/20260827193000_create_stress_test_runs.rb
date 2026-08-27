class CreateStressTestRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :stress_test_runs do |t|
      t.references :stress_test, null: false, foreign_key: true
      t.string :engine, null: false # historical | monte_carlo
      t.string :status, null: false, default: "pending"
      t.float :var_95
      t.float :var_99
      t.float :expected_shortfall
      t.float :sim_var_30d
      t.float :sim_expected_max_drawdown
      t.float :tail_risk_probability
      t.integer :elapsed_ms
      t.text :error_message
      t.json :payload, default: {}
      t.timestamps
    end
    add_index :stress_test_runs, [:stress_test_id, :engine], unique: true

    change_table :stress_tests do |t|
      t.integer :wall_elapsed_ms
      t.float :sim_var_30d
      t.float :sim_expected_max_drawdown
      t.float :tail_risk_probability
      t.integer :historical_elapsed_ms
      t.integer :monte_carlo_elapsed_ms
    end
  end
end
