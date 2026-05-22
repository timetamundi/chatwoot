# frozen_string_literal: true

# Job responsavel por enviar o payload de conversa resolvida para o CRMundi.
# Executado de forma assincrona pelo Sidekiq - nunca bloqueia a resolucao da conversa.
class CrmundiWebhookJob < ApplicationJob
  queue_as :default

  # sidekiq_options so existe quando o adaptador for Sidekiq
  sidekiq_options retry: 3 if respond_to?(:sidekiq_options)

  def perform(conversation_id)
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

    payload = build_payload(conversation)
    headers = build_headers(conversation)

    response = RestClient.post(url, payload.to_json, headers)

    Rails.logger.info(
      "[CRMundi] Webhook enviado com sucesso. Conversa #{conversation.id}, status HTTP #{response.code}"
    )
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

  def build_headers(conversation)
    headers = {
      content_type: :json,
      accept: :json,
      'X-Tenant-Id' => crmundi_tenant_id(conversation)
    }

    token = ENV.fetch('CRMUNDI_WEBHOOK_TOKEN', '').strip
    headers['Authorization'] = "Bearer #{token}" if token.present?

    headers
  end

  # Usa o slug/id do tenant no CRMundi (CRMUNDI_TENANT_ID).
  # Fallback para account_id numerico do Chatwoot se nao configurado.
  def crmundi_tenant_id(conversation)
    ENV.fetch('CRMUNDI_TENANT_ID', '').strip.presence || conversation.account_id.to_s
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
