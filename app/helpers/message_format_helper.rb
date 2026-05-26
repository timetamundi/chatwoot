module MessageFormatHelper
  MARKDOWN_TO_PLAINTEXT = lambda do |content|
    if defined?(Commonmarker)
      Commonmarker.to_plaintext(content)
    elsif defined?(CommonMarker)
      CommonMarker.render_doc(content).to_plaintext
    else
      content.to_s
    end
  end

  def transform_user_mention_content(message_content)
    # attachment message without content, message_content is nil
    return '' unless message_content.presence

    # Use CommonMarker to convert markdown to plain text for notifications
    # This handles all markdown formatting (links, bold, italic, etc.) not just mentions
    # Converts: [@👍 customer support](mention://team/1/%F0%9F%91%8D%20customer%20support)
    # To: @👍 customer support
    MARKDOWN_TO_PLAINTEXT.call(message_content).to_s.strip
  end

  def render_message_content(message_content)
    ChatwootMarkdownRenderer.new(message_content).render_message
  end
end
