# frozen_string_literal: true

# Listener que escuta o evento conversation_resolved e, se a conversa
# for de canal WhatsApp/Evolution, enfileira o CrmundiWebhookJob.
#
# Registrado em: app/dispatchers/async_dispatcher.rb
class CrmundiWebhookListener < BaseListener
  def conversation_resolved(event)
    return unless crmundi_enabled?

    conversation = extract_conversation_and_account(event)[0]

    # Filtra apenas conversas de canal WhatsApp
    unless whatsapp_conversation?(conversation)
      Rails.logger.debug("[CRMundi] Ignorando conversa #{conversation.id}: não é canal WhatsApp.")
      return
    end

    # TODO: Adicionar filtros de label/categoria quando disponíveis.
    # Exemplo: return if conversation.labels.include?('spam', 'reembolso', 'reclamacao', 'pos-venda')
    # Por ora, envia todas as conversas WhatsApp resolvidas.

    Rails.logger.info("[CRMundi] Conversa #{conversation.id} resolvida — enfileirando webhook.")
    CrmundiWebhookJob.perform_later(conversation.id)
  rescue StandardError => e
    # Nunca deve quebrar o fluxo de resolução da conversa
    Rails.logger.error("[CRMundi] Erro no listener para conversa #{conversation&.id}: #{e.message}")
  end

  private

  def crmundi_enabled?
    ENV.fetch('CRMUNDI_WEBHOOK_ENABLED', 'false').to_s.downcase == 'true' &&
      ENV['CRMUNDI_WEBHOOK_URL'].present?
  end

  def whatsapp_conversation?(conversation)
    inbox = conversation.inbox
    return false unless inbox

    # Channel::Whatsapp cobre Evolution API, WhatsApp Cloud, 360dialog, etc.
    # Channel::TwilioSms com medium=whatsapp também é considerado
    return true if inbox.channel_type == 'Channel::Whatsapp'
    return true if inbox.channel_type == 'Channel::TwilioSms' && inbox.channel.try(:medium) == 'whatsapp'

    false
  end
end
