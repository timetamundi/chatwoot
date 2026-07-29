# frozen_string_literal: true

module Chatmundi
  class EnsureTechnicalUserAccessService
    TECHNICAL_EMAIL = 'tecnologia@metamundi.com.br'.freeze
    TECHNICAL_NAME = 'Tecnologia CRMundi'.freeze

    def self.call(account: nil, inbox: nil)
      new(account: account, inbox: inbox).call
    end

    def initialize(account: nil, inbox: nil)
      @account = account
      @inbox = inbox
    end

    def call
      ActiveRecord::Base.transaction do
        user = ensure_technical_user
        accounts.each { |account| ensure_account_user(account, user) }
        inboxes.each { |inbox| ensure_inbox_member(inbox, user) }
        user
      end
    end

    private

    attr_reader :account, :inbox

    def ensure_technical_user
      user = User.find_or_initialize_by(email: TECHNICAL_EMAIL)
      if user.new_record?
        password = SecureRandom.base58(32)
        user.assign_attributes(
          name: TECHNICAL_NAME,
          password: password,
          password_confirmation: password,
          confirmed_at: Time.current,
          type: 'SuperAdmin'
        )
      elsif user.type != 'SuperAdmin'
        user.type = 'SuperAdmin'
      end
      user.save! if user.new_record? || user.changed?
      user
    end

    def accounts
      return Account.all if account.blank? && inbox.blank?
      return [account] if account.present?

      [inbox.account]
    end

    def inboxes
      return Inbox.all if account.blank? && inbox.blank?
      return account.inboxes if account.present?

      [inbox]
    end

    def ensure_account_user(account, user)
      account_user = account.account_users.find_or_initialize_by(user: user)
      account_user.role = :administrator
      account_user.save! if account_user.new_record? || account_user.changed?
    end

    def ensure_inbox_member(inbox, user)
      inbox.inbox_members.find_or_create_by!(user: user)
    end
  end
end
