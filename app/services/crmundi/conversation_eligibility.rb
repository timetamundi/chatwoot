# frozen_string_literal: true

module Crmundi
  # Centraliza as regras de elegibilidade de conversa para o webhook CRMundi.
  # Usado pelo CrmundiWebhookListener (resolved) e CrmundiInactiveConversationsScannerJob.
  module ConversationEligibility
    module_function

    # Retorna true se a conversa for de canal WhatsApp ou Evolution.
    #
    # Canais aceitos:
    #   - Channel::Whatsapp (todos: Evolution API, WhatsApp Cloud, 360dialog)
    #   - Channel::TwilioSms com medium whatsapp
    #   - Channel::Api quando:
    #       a) account.custom_attributes["evolution_instance"] presente  (caso real de producao)
    #       b) inbox.name contem "evolution"  (fallback por nome)
    def whatsapp_or_evolution?(conversation)
      inbox = conversation.inbox
      return false unless inbox

      channel_type = inbox.channel_type.to_s

      return true if channel_type == 'Channel::Whatsapp'
      return true if channel_type == 'Channel::TwilioSms' && inbox.channel.try(:medium) == 'whatsapp'

      if channel_type == 'Channel::Api'
        # Caso real: account tem evolution_instance em custom_attributes
        evolution_instance = conversation.account
                                         &.custom_attributes
                                         &.dig('evolution_instance')
                                         .to_s.strip
        return true if evolution_instance.present?

        # Fallback: nome do inbox contem "evolution"
        return true if inbox.name.to_s.downcase.include?('evolution')
      end

      false
    end

    # Retorna o tenant CRMundi salvo na Account via SSO, ou nil se ausente.
    # (mesma logica do CrmundiWebhookJob — centralizada aqui para nao duplicar)
    def tenant_for(conversation)
      attrs = conversation.account&.custom_attributes || {}

      t = attrs['crmundi_tenant_name'].to_s.strip
      return t if t.present?

      legacy = attrs['tenant_id'].to_s.strip
      return legacy if legacy.present?

      nil
    end
  end
end
