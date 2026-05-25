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

    last_msg = messages.last
    last_message_text = last_message_label(last_msg)

    {
      phone: conversation.contact&.phone_number,
      contact_id: contact_identifier(conversation),
      conversation_id: conversation.id.to_s,
      contact_name: conversation.contact&.name,
      last_message: last_message_text,
      conversation: messages
    }
  end

  # Retorna o texto a exibir como last_message no payload CRMundi.
  def last_message_label(serialized_msg)
    return nil if serialized_msg.nil?

    return serialized_msg[:content] if serialized_msg[:content].present?

    # Mensagem so com anexos — escolhe label por tipo
    attachments = serialized_msg[:attachments] || []
    if attachments.any? { |a| a[:file_type] == 'image' }
      '[imagem enviada]'
    elsif attachments.any?
      '[arquivo enviado]'
    end
  end

  # Aceita mensagens humanas (cliente ou agente), nao-privadas, com texto OU anexos.
  # Exclui mensagens de atividade (message_type == "activity").
  def valid_message?(message)
    return false if message.try(:private?)
    return false if message.try(:activity?)

    has_content    = message.content.present?
    has_attachment = message.attachments.any?

    return false unless has_content || has_attachment

    message.incoming? || message.outgoing?
  end

  # Padrao LLM: "user" para cliente, "assistant" para agente.
  def serialize_message(message)
    attachments = serialize_attachments(message)

    serialized = {
      role:      message.incoming? ? 'user' : 'assistant',
      content:   message.content.presence,
      timestamp: message.created_at.iso8601
    }

    if attachments.any?
      serialized[:message_type] = 'attachment'
      serialized[:attachments]  = attachments
      Rails.logger.info(
        "[CRMundi] Mensagem #{message.id} com #{attachments.size} anexo(s): " \
        "#{attachments.map { |a| a[:file_name] }.join(', ')}"
      )
    end

    serialized
  end

  # Serializa os anexos de uma mensagem.
  def serialize_attachments(message)
    message.attachments.map do |attachment|
      file_type    = attachment.file_type.to_s
      file_name    = attachment.file.attached? ? attachment.file.filename.to_s : nil
      content_type = attachment.file.attached? ? attachment.file.blob&.content_type : nil
      download_url = attachment.download_url.presence || attachment.external_url.presence

      {
        file_type:    file_type,
        file_name:    file_name,
        content_type: content_type,
        download_url: download_url
      }
    end
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
