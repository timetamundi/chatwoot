module Chatwoot
  class SsoSettings
    TAGS_PADRAO = %w[whitelabel crmundi].freeze

    class << self
      def normalize(raw) = raw.to_s.strip.downcase

      def find_account_by_tenant(raw)
        tenant = normalize(raw)
        Account.where("lower(custom_attributes->>'tenant_id') = ?", tenant).first
      end

      def criar_conta_para_tenant(raw, usuario)
        tenant = normalize(raw)
        Account.transaction do
          if (acc = find_account_by_tenant(tenant))
            return acc
          end

          acc = Account.create!(
            name: tenant.upcase,
            custom_attributes: { 'tenant_id' => tenant },
            locale: 'pt_BR'
          )

          acc.account_users.find_or_create_by!(user: usuario) do |au|
            au.role = :administrator
          end

          if acc.respond_to?(:tag_list)
            TAGS_PADRAO.each { |tag| acc.tag_list.add(tag) }
            acc.save!
          else
            acc.update!(custom_attributes: acc.custom_attributes.merge('tags' => TAGS_PADRAO))
          end

          acc
        end
      rescue ActiveRecord::RecordNotUnique
        find_account_by_tenant(tenant)
      end
    end
  end
end
