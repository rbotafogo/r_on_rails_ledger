# frozen_string_literal: true

module Docs
  # Allowlisted markdown pages under Rails.root/docs
  class Catalog
    Page = Struct.new(:slug, :title, :summary, :filename, keyword_init: true)

    PAGES = [
      Page.new(slug: "getting-started", title: "Getting started", summary: "Boot the app, Galaaz, seed data.", filename: "getting_started.md"),
      Page.new(slug: "product-scenario", title: "Product scenario", summary: "What the family-office stress demo is for.", filename: "product_scenario.md"),
      Page.new(slug: "architecture", title: "Architecture", summary: "Honest stack: proxies, Arrow handoff, no fake zero-copy.", filename: "architecture.md"),
      Page.new(slug: "implementation-plan", title: "Implementation plan", summary: "Phase checklist for this demo.", filename: "implementation_plan.md"),
      Page.new(slug: "data-and-seeding", title: "Data and seeding", summary: "GBM panel, insert_all, SEED_PROFILE.", filename: "data_and_seeding.md"),
      Page.new(slug: "engines-and-dashboard", title: "Engines and dashboard", summary: "Dual engines, KPIs, Plotly charts.", filename: "engines_and_dashboard.md"),
      Page.new(slug: "runbook", title: "Runbook", summary: "Ops, demo checklist, 2–3 min pitch script.", filename: "runbook.md"),
      Page.new(slug: "for-r-scientists", title: "For R scientists", summary: "Minimal Rails to ship with your R.", filename: "for_r_scientists.md"),
      Page.new(slug: "for-ruby-developers", title: "For Ruby developers", summary: "Call R safely from jobs.", filename: "for_ruby_developers.md"),
      Page.new(slug: "galaaz-api", title: "Galaaz API cheat sheet", summary: "Eval, Arrow, timeouts used here.", filename: "galaaz_api_cheatsheet.md"),
      Page.new(slug: "ruby-dsl", title: "Ruby DSL & code", summary: "Galaaz call style + this app’s engine code.", filename: "ruby_dsl.md"),
      Page.new(slug: "external-references", title: "External references", summary: "Galaaz Pages, Rails Solid, R packages.", filename: "external_references.md")
    ].freeze

    def self.all
      PAGES
    end

    def self.find(slug)
      PAGES.find { |p| p.slug == slug }
    end

    def self.path_for(page)
      Rails.root.join("docs", page.filename)
    end

    def self.read!(page)
      path = path_for(page)
      raise ActiveRecord::RecordNotFound, "Missing #{page.filename}" unless path.file?

      path.read
    end
  end
end
