# frozen_string_literal: true

# Job responsável por enviar o payload de conversa resolvida para o CRMundi.
# Executa de forma assíncrona para não bloquear a resolução da conversa.
class CrmundiWebhookJob < ApplicationJob
  queue_as :low

  # Tempo máximo de espera antes de desistir
  sidekiq_options retry: 3, dead: false

  def perform(conversation_id)
    return unless crmundi_enabled?

    conversation = Conversation.find_by(id: conversation_id)
    unless conversation
      Rails.logger.warn("[CRMundi] Conversa #{conversation_id} não encontrada, ignorando.")
      return
    end

    payload = build_payload(conversation)
    send_to_crmundi(payload, conversation)
  end

  private

  def crmundi_enabled?
    ENV.fetch('CRMUNDI_WEBHOOK_ENABLED', 'false').to_s.downcase == 'true' &&
      ENV['CRMUNDI_WEBHOOK_URL'].present?
  end

  def build_payload(conversation)
    contact       = conversation.contact
    contact_inbox = conversation.contact_inbox

    # source_id para WhatsApp/Evolution é algo como "5511999999999@s.whatsapp.net"
    whatsapp_source_id = contact_inbox&.source_id.to_s

    # Tenta extrair número limpo do source_id ou do campo phone_number do contato
    phone = extract_phone(contact, whatsapp_source_id)

    messages = build_conversation_history(conversation)
    last_message = messages.last&.dig(:content).to_s

    {
      phone: phone,
      contact_id: whatsapp_source_id,
      conversation_id: conversation.id.to_s,
      contact_name: contact&.name.to_s,
      last_message: last_message,
      conversation: messages
    }
  end

  def extract_phone(contact, source_id)
    # Prefere o phone_number cadastrado no contato
    return contact.phone_number if contact&.phone_number.present?

    # Tenta extrair do source_id WhatsApp: "5511999999999@s.whatsapp.net" → "+5511999999999"
    if source_id.include?('@')
      number = source_id.split('@').first
      return "+#{number}" if number.match?(/\A\d+\z/)
    end

    source_id
  end

  def build_conversation_history(conversation)
    # Busca todas as mensagens de chat (exclui atividade/sistema/privadas)
    conversation.messages
                .chat
                .where(private: false)
                .order(created_at: :asc)
                .map do |msg|
                  role = msg.incoming? ? 'client' : 'agent'
                  {
                    role: role,
                    content: msg.content.to_s,
                    timestamp: msg.created_at.iso8601
                  }
                end
  end

  def send_to_crmundi(payload, conversation)
    url   = ENV.fetch('CRMUNDI_WEBHOOK_URL', nil)
    token = ENV.fetch('CRMUNDI_WEBHOOK_TOKEN', nil)

    headers = {
      'Content-Type'  => 'application/json',
      'X-Tenant-Id'   => conversation.account_id.to_s
    }
    headers['Authorization'] = "Bearer #{token}" if token.present?

    response = RestClient::Request.execute(
      method: :post,
      url: url,
      payload: payload.to_json,
      headers: headers,
      timeout: 10,
      open_timeout: 5
    )

    Rails.logger.info(
      "[CRMundi] Webhook enviado com sucesso. Conversa #{conversation.id}, status HTTP #{response.code}"
    )
  rescue RestClient::ExceptionWithResponse => e
    Rails.logger.error(
      "[CRMundi] Falha no webhook. Conversa #{conversation.id}, " \
      "status HTTP #{e.response&.code}, body: #{e.response&.body.to_s.truncate(300)}"
    )
  rescue StandardError => e
    # Loga o erro mas NÃO propaga — a resolução da conversa já ocorreu
    Rails.logger.error("[CRMundi] Erro ao enviar webhook para conversa #{conversation.id}: #{e.message}")
  end
end
