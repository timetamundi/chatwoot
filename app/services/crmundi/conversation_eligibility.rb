# frozen_string_literal: true

module Crmundi
  # Centraliza as regras de elegibilidade de conversa para o webhook CRMundi.
  # Usado pelo CrmundiWebhookListener (resolved) e CrmundiInactiveConversationsScannerJob.
  module ConversationEligibility
    module_function    # Retorna true se a conversa for de canal WhatsApp ou Evolution.
    #
    # Canais aceitos:
    #   - Channel::Whatsapp (todos: Evolution API, WhatsApp Cloud, 360dialog)
    #   - Channel::TwilioSms com medium whatsapp
    #   - Channel::Api quando:
    #       a) account.custom_attributes["evolution_instance"] presente
    #       b) inbox.name contem "evolution"
    #       c) account tem tenant CRMundi configurado (crmundi_tenant_name ou tenant_id)
    #          → qualquer Channel::Api de account CRMundi e elegivel
    #          → o job bloqueia o envio se nao houver tenant de qualquer forma
    def whatsapp_or_evolution?(conversation)
      return false if group_conversation?(conversation)

      inbox = conversation.inbox
      return false unless inbox

      channel_type = inbox.channel_type.to_s

      return true if channel_type == 'Channel::Whatsapp'
      return true if channel_type == 'Channel::TwilioSms' && inbox.channel.try(:medium) == 'whatsapp'

      if channel_type == 'Channel::Api'
        # a) evolution_instance explicito em custom_attributes
        evolution_instance = conversation.account
                                         &.custom_attributes
                                         &.dig('evolution_instance')
                                         .to_s.strip
        return true if evolution_instance.present?

        # b) nome do inbox contem "evolution"
        return true if inbox.name.to_s.downcase.include?('evolution')

        # c) account tem tenant CRMundi — qualquer Channel::Api dessa account e elegivel
        #    (caso real de producao: inbox "Mensagens" sem evolution_instance no nome)
        return true if tenant_for(conversation).present?
      end

      false
    end

    # Grupos do WhatsApp (Baileys/Evolution) nao tem um numero de telefone unico
    # associado ao contato — o payload de lead do CRMundi exige "phone" (string
    # obrigatoria), entao grupos nunca sao elegiveis para virar Lead/Deal no Pipeline.
    def group_conversation?(conversation)
      identifier = conversation.contact&.identifier.to_s
      identifier.end_with?('@g.us')
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
