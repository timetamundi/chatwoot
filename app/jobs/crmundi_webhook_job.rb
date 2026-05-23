# frozen_string_literal: true

# Job responsavel por enviar o payload de conversa resolvida/inativa para o CRMundi.
# Executado de forma assincrona pelo Sidekiq — nunca bloqueia a resolucao da conversa.
#
# O X-Tenant-Id e resolvido EXCLUSIVAMENTE via account.custom_attributes, populado
# automaticamente pelo SSO CRMundi → ChatMundi. Sem fallback por ENV manual.
class CrmundiWebhookJob < ApplicationJob
  queue_as :default

  # sidekiq_options so existe quando o adaptador for Sidekiq
  sidekiq_options retry: 3 if respond_to?(:sidekiq_options)

  # reason: "resolved" (botao Resolver) ou "inactivity_Nmin" (scanner de inatividade)
  def perform(conversation_id, reason = 'resolved')
    unless crmundi_enabled?
      log_info('Webhook desabilitado (CRMUNDI_WEBHOOK_ENABLED != true)')
      return
    end

    url = ENV.fetch('CRMUNDI_WEBHOOK_URL', '').strip
    if url.blank?
      log_info('URL nao configurada (CRMUNDI_WEBHOOK_URL vazia)')
      return
    end

    conversation = Conversation.find_by(id: conversation_id)
    unless conversation
      log_info("Conversa #{conversation_id} nao encontrada, ignorando.")
      return
    end

    # Bloqueia envio se nao houver tenant salvo na Account via SSO
    tenant_id = crmundi_tenant_id(conversation)
    return if tenant_id.blank?

    payload = build_payload(conversation)
    headers = build_headers(conversation, tenant_id)

    response = RestClient.post(url, payload.to_json, headers)

    Rails.logger.info(
      "[CRMundi] Webhook enviado com sucesso. Conversa #{conversation.id}, status HTTP #{response.code}"
    )

    # Marca a conversa como enviada APENAS apos sucesso HTTP (evita duplicidade futura)
    mark_conversation_as_sent!(conversation, reason)
  rescue StandardError => e
    Rails.logger.error(
      "[CRMundi] Falha ao enviar webhook. Conversa #{conversation_id}. " \
      "Erro: #{e.class} - #{e.message}"
    )
    raise e # permite que o Sidekiq faca retry automatico
  end

  private

  def crmundi_enabled?
    ENV.fetch('CRMUNDI_WEBHOOK_ENABLED', 'false').strip == 'true'
  end

  def build_headers(conversation, tenant_id)
    headers = {
      content_type: :json,
      accept: :json,
      'X-Tenant-Id'            => tenant_id,
      'X-Chatmundi-Account-Id' => conversation.account_id.to_s
    }
    token = ENV.fetch('CRMUNDI_WEBHOOK_TOKEN', '').strip
    headers['Authorization'] = "Bearer #{token}" if token.present?
    headers
  end

  # Delega ao service compartilhado — sem duplicar logica de tenant.
  def crmundi_tenant_id(conversation)
    account_id = conversation.account_id.to_s
    tenant = Crmundi::ConversationEligibility.tenant_for(conversation)

    if tenant.present?
      Rails.logger.info("[CRMundi] Tenant resolvido para account_id=#{account_id}: #{tenant}")
      return tenant
    end

    Rails.logger.error(
      "[CRMundi] Webhook nao enviado: account_id=#{account_id} sem crmundi_tenant_name/tenant_id " \
      "em custom_attributes. O usuario precisa acessar via SSO CRMundi primeiro."
    )
    nil
  end

  # Salva metadata de envio na conversa para garantir idempotencia.
  # So chamado apos POST HTTP bem-sucedido.
  def mark_conversation_as_sent!(conversation, reason)
    attrs = (conversation.custom_attributes || {}).dup
    attrs['crmundi_webhook_sent_at'] = Time.current.iso8601
    attrs['crmundi_webhook_reason']  = reason
    conversation.update!(custom_attributes: attrs)
    Rails.logger.info(
      "[CRMundi] Conversa #{conversation.id} marcada como enviada ao CRMundi. reason=#{reason}"
    )
  rescue StandardError => e
    # Nao propaga — o webhook ja foi enviado com sucesso; falha na marcacao e secundaria
    Rails.logger.error(
      "[CRMundi] Falha ao marcar conversa #{conversation.id} como enviada: #{e.class} - #{e.message}"
    )
  end

  def build_payload(conversation)
    messages = conversation.messages
                           .order(:created_at)
                           .select { |msg| valid_message?(msg) }
                           .map { |msg| serialize_message(msg) }

    {
      phone: conversation.contact&.phone_number,
      contact_id: contact_identifier(conversation),
      conversation_id: conversation.id.to_s,
      contact_name: conversation.contact&.name,
      last_message: messages.last&.dig(:content),
      conversation: messages
    }
  end

  # Aceita apenas mensagens humanas (cliente ou agente), com texto, nao-privadas.
  def valid_message?(message)
    return false if message.try(:private?)
    return false if message.content.blank?

    message.incoming? || message.outgoing?
  end

  # Padrao LLM: "user" para cliente, "assistant" para agente.
  def serialize_message(message)
    {
      role: message.incoming? ? 'user' : 'assistant',
      content: message.content,
      timestamp: message.created_at.iso8601
    }
  end

  # Retorna o identificador do contato no canal.
  # Para WhatsApp/Evolution: "5511999999999@s.whatsapp.net"
  def contact_identifier(conversation)
    conversation.contact&.identifier.presence ||
      conversation.contact_inbox&.source_id.presence ||
      conversation.contact&.phone_number
  end

  def log_info(message)
    Rails.logger.info("[CRMundi] #{message}")
  end
end
