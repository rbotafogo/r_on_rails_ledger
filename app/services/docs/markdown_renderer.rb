# frozen_string_literal: true

module Docs
  class MarkdownRenderer
    def self.to_html(markdown)
      new.render(markdown)
    end

    def render(markdown)
      html = engine_html(markdown.to_s)
      rewrite_doc_links(html)
    end

    private

    def rewrite_doc_links(html)
      by_file = Docs::Catalog.all.to_h { |p| [p.filename, p.slug] }
      html.gsub(%r{href="(\./)?([^"/]+\.md)"}) do
        file = Regexp.last_match(2)
        slug = by_file[file] || file.delete_suffix(".md").tr("_", "-")
        %(href="/docs/#{slug}")
      end
    end

    def engine_html(markdown)
      if RUBY_ENGINE == "jruby"
        require "kramdown"
        require "kramdown-parser-gfm"
        Kramdown::Document.new(markdown, input: "GFM", hard_wrap: false).to_html
      else
        redcarpet.render(markdown)
      end
    end

    def redcarpet
      @redcarpet ||= ::Redcarpet::Markdown.new(
        ::Redcarpet::Render::HTML.new(
          filter_html: true,
          hard_wrap: false,
          with_toc_data: true
        ),
        autolink: true,
        fenced_code_blocks: true,
        tables: true,
        strikethrough: true,
        no_intra_emphasis: true
      )
    end
  end
end
