# frozen_string_literal: true

# Listener que escuta o evento conversation_resolved e, se a conversa
# for de canal WhatsApp/Evolution, enfileira o CrmundiWebhookJob.
#
# A logica de elegibilidade de canal e delegada a:
#   Crmundi::ConversationEligibility
#
# Registrado em: app/dispatchers/async_dispatcher.rb
class CrmundiWebhookListener < BaseListener
  def conversation_resolved(event)
    conversation = event.data[:conversation]
    return unless conversation

    unless Crmundi::ConversationEligibility.whatsapp_or_evolution?(conversation)
      Rails.logger.info("[CRMundi] Conversa #{conversation.id} ignorada: canal nao WhatsApp/Evolution")
      return
    end

    # TODO: filtrar por labels quando disponivel.
    # Exemplo: return if (conversation.labels & %w[spam reembolso reclamacao pos-venda]).any?

    Rails.logger.info("[CRMundi] Conversa #{conversation.id} resolvida - enfileirando webhook.")
    CrmundiWebhookJob.perform_later(conversation.id, 'resolved')
  rescue StandardError => e
    # Nunca propaga - a resolucao da conversa ja ocorreu
    Rails.logger.error("[CRMundi] Erro no listener para conversa #{conversation&.id}: #{e.message}")
  end
end
