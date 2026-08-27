# frozen_string_literal: true

class DocsController < ApplicationController
  def index
    @pages = Docs::Catalog.all
  end

  def show
    @page = Docs::Catalog.find(params[:id])
    raise ActiveRecord::RecordNotFound, "Unknown doc" unless @page

    markdown = Docs::Catalog.read!(@page)
    @html = Docs::MarkdownRenderer.to_html(markdown)
    @excerpts = @page.slug == "ruby-dsl" ? Docs::CodeExcerpts.all : []
  end
end
