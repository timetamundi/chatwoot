# frozen_string_literal: true

# Scanner que procura conversas WhatsApp/Evolution abertas sem nova mensagem
# ha pelo menos CRMUNDI_INACTIVITY_MINUTES minutos e enfileira CrmundiWebhookJob.
#
# Rodado pelo sidekiq-cron a cada 5 minutos (config/schedule.yml).
# Controlado por: CRMUNDI_INACTIVITY_WEBHOOK_ENABLED=true/false
#
# Idempotencia: nao reenvia se conversation.custom_attributes["crmundi_webhook_sent_at"] presente.
# Marcacao feita pelo CrmundiWebhookJob apos POST HTTP bem-sucedido.
class CrmundiInactiveConversationsScannerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    unless inactivity_webhook_enabled?
      Rails.logger.info('[CRMundi] Scanner de inatividade desabilitado (CRMUNDI_INACTIVITY_WEBHOOK_ENABLED != true)')
      return
    end

    minutes   = inactivity_minutes
    reason    = "inactivity_#{minutes}min"
    threshold = Time.current - minutes.minutes

    Rails.logger.info("[CRMundi] Scanner iniciado. Buscando conversas sem mensagem desde #{threshold.iso8601}")

    candidates = fetch_candidates(threshold)
    Rails.logger.info("[CRMundi] #{candidates.size} conversa(s) candidata(s) encontrada(s)")

    enqueued = 0
    skipped  = 0

    candidates.each do |conversation|
      result = process_conversation(conversation, reason, threshold)
      result == :enqueued ? enqueued += 1 : skipped += 1
    end

    Rails.logger.info("[CRMundi] Scanner concluido. Enfileiradas=#{enqueued} Ignoradas=#{skipped}")
  rescue StandardError => e
    Rails.logger.error("[CRMundi] Erro no scanner de inatividade: #{e.class} - #{e.message}")
    # Nao propaga — falha no scanner nao deve impactar outros jobs
  end

  private

  # ─── Configuracao ─────────────────────────────────────────────────────────

  def inactivity_webhook_enabled?
    ENV.fetch('CRMUNDI_INACTIVITY_WEBHOOK_ENABLED', 'false').strip == 'true'
  end

  def inactivity_minutes
    ENV.fetch('CRMUNDI_INACTIVITY_MINUTES', '30').to_i.clamp(1, 1440)
  end

  # ─── Busca de candidatos ───────────────────────────────────────────────────
  # Busca conversas abertas/pending atualizadas nos ultimos 7 dias em batches.
  # Filtragem fina e feita em Ruby apos carga por batch para evitar queries SQL complexas.
  def fetch_candidates(threshold)
    results = []
    Conversation
      .where(status: %w[open pending])
      .where('updated_at >= ?', 7.days.ago)
      .includes(:inbox, :account, :contact)
      .find_each(batch_size: 100) do |conv|
        results << conv if eligible?(conv, threshold)
      end
    results
  end

  # ─── Elegibilidade ────────────────────────────────────────────────────────

  def eligible?(conversation, threshold)
    # 1. Canal WhatsApp/Evolution
    unless Crmundi::ConversationEligibility.whatsapp_or_evolution?(conversation)
      return false
    end

    # 2. Ja enviado antes — nao reenviar
    if already_sent?(conversation)
      Rails.logger.info("[CRMundi] Conversa #{conversation.id} ignorada: webhook CRMundi ja enviado")
      return false
    end

    # 3. Tem tenant salvo na account
    unless Crmundi::ConversationEligibility.tenant_for(conversation).present?
      Rails.logger.info("[CRMundi] Conversa #{conversation.id} ignorada: account sem tenant CRMundi")
      return false
    end

    # 4. Tem pelo menos uma mensagem incoming (do cliente)
    public_messages = public_messages_for(conversation)
    return false unless public_messages.any?(&:incoming?)

    # 5. Ultima mensagem publica foi antes do threshold (inativa ha >= N minutos)
    last_public_at = public_messages.map(&:created_at).max
    return false unless last_public_at && last_public_at <= threshold

    true
  end
  def already_sent?(conversation)
    conversation.custom_attributes&.dig('crmundi_webhook_sent_at').present?
  end

  def public_messages_for(conversation)
    # Carrega mensagens com attachments em batch para evitar N+1
    msgs = conversation.messages.includes(:attachments).load
    msgs.select do |msg|
      next false if msg.try(:private?)
      next false if msg.try(:activity?)

      has_content    = msg.content.present?
      has_attachment = msg.attachments.any?

      (has_content || has_attachment) && (msg.incoming? || msg.outgoing?)
    end
  end

  # ─── Processamento ────────────────────────────────────────────────────────
  def process_conversation(conversation, reason, threshold)
    last_public_at = public_messages_for(conversation).map(&:created_at).max
    minutes_inactive = last_public_at ? ((Time.current - last_public_at) / 60).round : '?'

    Rails.logger.info(
      "[CRMundi] Conversa #{conversation.id} inativa ha #{minutes_inactive} minutos - enfileirando webhook"
    )
    CrmundiWebhookJob.perform_later(conversation.id, reason)
    :enqueued
  rescue StandardError => e
    Rails.logger.error(
      "[CRMundi] Erro ao processar conversa #{conversation.id} no scanner: #{e.class} - #{e.message}"
    )
    :skipped
  end
end
