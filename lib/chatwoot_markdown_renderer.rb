class ChatwootMarkdownRenderer
  def initialize(content)
    @content = content
  end

  def render_message(hardbreaks: false)
    markdown_renderer = BaseMarkdownRenderer.new(options: hardbreaks ? [:HARDBREAKS] : :DEFAULT)
    doc = parse_markdown(@content, hardbreaks: hardbreaks)
    html = markdown_renderer.render(doc)
    render_as_html_safe(html)
  end

  def render_article
    markdown_renderer = CustomMarkdownRenderer.new
    doc = parse_markdown(@content)
    html = markdown_renderer.render(doc)

    render_as_html_safe(html)
  end

  def render_markdown_to_plain_text
    if defined?(Commonmarker)
      Commonmarker.to_plaintext(@content)
    else
      CommonMarker.render_doc(@content, :DEFAULT).to_plaintext
    end
  end

  private

  def parse_markdown(content, hardbreaks: false)
    if defined?(Commonmarker)
      Commonmarker.parse(content, options: hardbreaks ? [:HARDBREAKS] : :DEFAULT)
    else
      CommonMarker.render_doc(content, :DEFAULT, [:strikethrough, :autolink])
    end
  end

  def render_as_html_safe(html)
    # rubocop:disable Rails/OutputSafety
    html.html_safe
    # rubocop:enable Rails/OutputSafety
  end
end
