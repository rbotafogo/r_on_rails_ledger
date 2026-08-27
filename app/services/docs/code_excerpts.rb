# frozen_string_literal: true

module Docs
  # Pull short excerpts from this app’s source for the Ruby DSL guide.
  class CodeExcerpts
    Excerpt = Struct.new(:title, :path, :code, keyword_init: true)

    def self.all
      [
        excerpt(
          "Arrow handoff (Ruby columns → R Arrow Table)",
          "app/services/risk/arrow_handoff.rb",
          /def to_returns_table.*?^    end$/m
        ),
        excerpt(
          "Historical VaR as Ruby methods calling R.*",
          "app/services/risk/historical_engine.rb",
          /def historical_var.*?def return_density.*?^    end$/m
        ),
        excerpt(
          "Local path: Arrow numeric → DSL KPIs",
          "app/services/risk/historical_engine.rb",
          /def local_arrow_dsl.*?^    end$/m
        ),
        excerpt(
          "Monte Carlo: R.mean / R.sd after Arrow",
          "app/services/risk/monte_carlo_engine.rb",
          /def mean_return.*?def sd_return.*?^    end$/m
        )
      ].compact
    end

    def self.excerpt(title, relative, pattern, strip_fences: false)
      path = Rails.root.join(relative)
      return nil unless path.file?

      body = path.read
      match = body.match(pattern)
      return nil unless match

      code = match[0]
      code = code.sub(/\A```ruby\n/, "").sub(/\n```\z/, "") if strip_fences
      code = code.lines.first(80).join
      Excerpt.new(title: title, path: relative, code: code.strip)
    end
  end
end
