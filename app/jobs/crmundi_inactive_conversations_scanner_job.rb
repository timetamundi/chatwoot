# frozen_string_literal: true

class CrmundiInactiveConversationsScannerJob < ApplicationJob
  queue_as :scheduled_jobs

  def perform
    unless inactivity_webhook_enabled?
      Rails.logger.info('[CRMundi] Scanner de inatividade desabilitado (CRMUNDI_INACTIVITY_WEBHOOK_ENABLED != true)')
      return
    end

    minutes = inactivity_minutes
    reason = "inactivity_#{minutes}min"
    threshold = Time.current - minutes.minutes
    max_per_run = inactivity_max_per_run

    Rails.logger.info(
      "[CRMundi] Scanner iniciado. threshold=#{threshold.iso8601} max_per_run=#{max_per_run} reason=#{reason}"
    )

    enqueued = 0
    skipped = 0

    Conversation
      .where(status: %w[open pending])
      .where('updated_at >= ?', 7.days.ago)
      .includes(:inbox, :account, :contact)
      .find_each(batch_size: 100) do |conversation|
      break if enqueued >= max_per_run

      if enqueue_inactivity_webhook(conversation, reason, threshold)
        enqueued += 1
      else
        skipped += 1
      end
    end

    Rails.logger.info("[CRMundi] Scanner concluido. Enfileiradas=#{enqueued} Ignoradas=#{skipped} Limite=#{max_per_run}")
  rescue StandardError => e
    Rails.logger.error("[CRMundi] Erro no scanner de inatividade: #{e.class} - #{e.message}")
  end

  private

  def inactivity_webhook_enabled?
    ENV.fetch('CRMUNDI_INACTIVITY_WEBHOOK_ENABLED', 'false').strip == 'true'
  end

  def inactivity_minutes
    ENV.fetch('CRMUNDI_INACTIVITY_MINUTES', '30').to_i.clamp(1, 1440)
  end

  def inactivity_max_per_run
    ENV.fetch('CRMUNDI_INACTIVITY_MAX_PER_RUN', '20').to_i.clamp(1, 200)
  end

  def enqueue_window_minutes
    ENV.fetch('CRMUNDI_INACTIVITY_ENQUEUE_WINDOW_MINUTES', '60').to_i.clamp(1, 1440)
  end

  def enqueue_inactivity_webhook(conversation, reason, threshold)
    return false unless eligible?(conversation, threshold)

    return false unless mark_enqueued_at!(conversation)

    CrmundiWebhookJob.perform_later(conversation.id, reason)
    true
  rescue StandardError => e
    Rails.logger.error("[CRMundi] Erro ao processar conversa #{conversation.id} no scanner: #{e.class} - #{e.message}")
    false
  end

  def eligible?(conversation, threshold)
    return false unless Crmundi::ConversationEligibility.whatsapp_or_evolution?(conversation)
    return false if already_sent?(conversation)
    return false unless Crmundi::ConversationEligibility.tenant_for(conversation).present?
    return false if recently_enqueued?(conversation)

    public_messages = public_messages_for(conversation)
    return false unless public_messages.any?(&:incoming?)

    last_public_at = public_messages.map(&:created_at).max
    return false unless last_public_at && last_public_at <= threshold

    true
  end

  def already_sent?(conversation)
    conversation.custom_attributes&.dig('crmundi_webhook_sent_at').present?
  end

  def recently_enqueued?(conversation)
    raw = conversation.custom_attributes&.dig('crmundi_inactivity_enqueued_at')
    return false if raw.blank?

    last_enqueued_at = Time.zone.parse(raw.to_s)
    return false if last_enqueued_at.blank?

    last_enqueued_at >= enqueue_window_minutes.minutes.ago
  rescue ArgumentError
    false
  end

  def mark_enqueued_at!(conversation)
    conversation.with_lock do
      conversation.reload
      return false if already_sent?(conversation)
      return false if recently_enqueued?(conversation)

      attrs = (conversation.custom_attributes || {}).dup
      attrs['crmundi_inactivity_enqueued_at'] = Time.current.iso8601
      conversation.update!(custom_attributes: attrs)
      true
    end
  end

  def public_messages_for(conversation)
    messages = conversation.messages.includes(:attachments).load
    messages.select do |message|
      next false if message.try(:private?)
      next false if message.try(:activity?)

      has_content = message.content.present?
      has_attachment = message.attachments.any?

      (has_content || has_attachment) && (message.incoming? || message.outgoing?)
    end
  end
end
