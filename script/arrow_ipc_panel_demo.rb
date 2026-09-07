# frozen_string_literal: true

# Stage B Arrow IPC demo on the demo portfolio (not the stress-test job).
# Usage (from r_on_rails_ledger):
#   bin/rails runner script/arrow_ipc_panel_demo.rb

require "galaaz"

abort "No portfolio — run: bin/rails db:seed" if Portfolio.none?

unless Galaaz::ArrowIpc.available?
  abort "Galaaz::ArrowIpc not available. CRuby: Apache Arrow GLib + gem install red-arrow " \
        "(match pkg-config --modversion arrow-glib). JRuby: GALAAZ_ARROW_JARS or ~/arrow_jars."
end

ok = R::Support.eval("isTRUE(requireNamespace('arrow', quietly = TRUE)) && isTRUE(requireNamespace('dplyr', quietly = TRUE))")
flag = ok.respond_to?(:>>) ? (ok >> 0) : ok
abort "Need R packages arrow and dplyr" unless flag == true

portfolio = Portfolio.first
rows = Risk::ReturnPanel.from_portfolio(portfolio, limit_per_asset: 200)
abort "No return rows" if rows.empty?

cols = Risk::ReturnPanel.column_hash(rows)
path = Galaaz::ArrowIpc.write(cols)
puts "B1 wrote IPC #{path} (#{rows.size} rows)"

tbl = R::Arrow.open_ipc(path)
Galaaz::ArrowIpc.release(path)

grouped = R.dplyr___group_by(tbl, :ticker)
summed = R.dplyr___summarise(
  grouped,
  n: E.n(),
  mean_ret: E.mean(:daily_return)
)

out_path = R::Arrow.write_ipc(summed)
result_rows = Galaaz::ArrowIpc.read_batches(out_path)
Galaaz::ArrowIpc.release(out_path)

puts "B2 read #{result_rows.size} ticker summaries:"
result_rows.each { |r| puts "  #{r.inspect}" }
