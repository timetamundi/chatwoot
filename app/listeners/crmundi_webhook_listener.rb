# frozen_string_literal: true

# Listener que escuta o evento conversation_resolved e, se a conversa
# for de canal WhatsApp/Evolution, enfileira o CrmundiWebhookJob.
#
# Registrado em: app/dispatchers/async_dispatcher.rb
class CrmundiWebhookListener < BaseListener
  def conversation_resolved(event)
    conversation = event.data[:conversation]
    return unless conversation

    unless crmundi_channel?(conversation)
      Rails.logger.info("[CRMundi] Conversa #{conversation.id} ignorada: canal nao WhatsApp/Evolution")
      return
    end

    # TODO: filtrar por labels quando disponivel.
    # Exemplo: return if (conversation.labels & %w[spam reembolso reclamacao pos-venda]).any?

    Rails.logger.info("[CRMundi] Conversa #{conversation.id} resolvida - enfileirando webhook.")
    CrmundiWebhookJob.perform_later(conversation.id)
  rescue StandardError => e
    # Nunca propaga - a resolucao da conversa ja ocorreu
    Rails.logger.error("[CRMundi] Erro no listener para conversa #{conversation&.id}: #{e.message}")
  end

  private

  # Canal compativel:
  # - Channel::Whatsapp  => Evolution API, WhatsApp Cloud, 360dialog (todos usam esse channel_type)
  # - Channel::TwilioSms com medium whatsapp
  # - Channel::Api cujo nome do inbox contenha "evolution" (caso Evolution seja configurado como API channel)
  def crmundi_channel?(conversation)
    inbox = conversation.inbox
    return false unless inbox

    channel_type = inbox.channel_type.to_s
    inbox_name   = inbox.name.to_s.downcase

    return true if channel_type == 'Channel::Whatsapp'
    return true if channel_type == 'Channel::TwilioSms' && inbox.channel.try(:medium) == 'whatsapp'

    # Evolution configurado como Channel::Api: identifica pelo nome do inbox
    return true if channel_type == 'Channel::Api' && inbox_name.include?('evolution')

    false
  end
end
