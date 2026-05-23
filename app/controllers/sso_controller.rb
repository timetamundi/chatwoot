require 'net/http'
require 'uri'
require 'json'
require 'jwt'
require 'jwt/jwk'
require 'rack/utils'

class SsoController < ApplicationController
  skip_forgery_protection
  skip_before_action :authenticate_user!, raise: false

  def crmundi
    jwt = params[:token].to_s
    raise 'SSO token ausente' if jwt.blank?

    request_tenant = resolve_tenant_from_request!
    payload = verify_with_jwks!(jwt, request_tenant)

    email  = payload['email'] || payload['sub']
    raise 'email/sub ausente no token' if email.blank?

    name   = payload['name'].presence || email.to_s.split('@').first
    sub    = payload['sub']
    tenant = payload['__resolved_tenant__'] # já normalizado
    raise 'tenant ausente' if tenant.blank?

    user    = find_or_create_user!(email: email, name: name, external_id: sub)
    account = find_or_create_account!(tenant)
    upsert_crmundi_tenant_mapping!(account, tenant)
    cw_role = (payload['cw_role'].presence || infer_role_from_payload(payload)).to_s
    cw_role = %w[administrator agent].include?(cw_role) ? cw_role : 'agent'

    link_user_to_account_with_role!(user, account, cw_role)

    # encerra sessões antigas e autentica
    begin
      sign_out_all_scopes
    rescue StandardError
      nil
    end
    sign_in(:user, user)

    # tokens do devise_token_auth
    auth = user.create_new_auth_token
    user.save!

    requested_next = params[:next].presence

    # Se vier URL absoluta, ignora; só aceitamos caminhos locais
    next_path =
      if requested_next&.match?(%r{\Ahttps?://}i)
        "/app/accounts/#{account.id}/dashboard"
      else
        (requested_next.presence || "/app/accounts/#{account.id}/dashboard").tap do |p|
          p.prepend('/') unless p.start_with?('/')
        end
      end

    fragment = Rack::Utils.build_query(
      'uid' => auth['uid'],
      'client' => auth['client'],
      'access-token' => auth['access-token'],
      'token-type' => auth['token-type'],
      'expiry' => auth['expiry'],
      'email' => email,
      'account_id' => account.id,
      'tenant' => tenant,
      'next' => next_path
    )

    front_base = frontend_for_tenant(tenant) # deve ser http://localhost:3000 em dev
    redirect_to "#{front_base}/sso/bootstrap##{fragment}"
  rescue StandardError => e
    Rails.logger.error("[SSO] #{e.class}: #{e.message}")
    render plain: "SSO error: #{e.message}", status: :unauthorized
  end

  def bootstrap
    render 'sso/bootstrap', layout: false
  end

  private

  def verify_with_jwks!(jwt, resolved_tenant)
    iss = ENV.fetch('SSO_JWT_ISS', 'crmundi')
    aud = ENV.fetch('SSO_JWT_AUD', 'chatmundi')

    # Lê header/payload sem verificar (para pegar kid)
    _, unverified_header = JWT.decode(jwt, nil, false)
    kid = unverified_header['kid'].presence || ENV['SSO_JWT_KID'].presence

    # tenant vem do request
    resolved_tenant = normalize_tenant(resolved_tenant)
    raise 'tenant ausente (request)' if resolved_tenant.blank?

    # Busca JWKS do tenant resolvido
    jwks_data = fetch_jwks!(tenant: resolved_tenant)
    keys = Array(jwks_data['keys'])
    raise "JWKS inválido: sem 'keys'. Body=#{jwks_data.inspect[0, 200]}" if keys.empty?

    jwk_hash =
      if kid
        keys.find { |k| k['kid'] == kid } ||
          raise("kid '#{kid}' não encontrado. Disponíveis: #{keys.map { |k| k['kid'] }.compact.join(', ')}")
      else
        keys.first
      end

    public_key = JWT::JWK.import(jwk_hash).public_key

    payload, = JWT.decode(
      jwt, public_key, true,
      algorithm: 'RS256',
      iss: iss, verify_iss: true,
      aud: aud, verify_aud: true,
      verify_iat: true, verify_exp: true,
      leeway: 60
    )

    # comparar APENAS com 'tenant' vindo no token (se vier)
    token_tenant =
      payload['tenant'].presence

    if token_tenant.present? && normalize_tenant(token_tenant) != resolved_tenant
      raise "tenant divergente (token=#{token_tenant} req=#{resolved_tenant})"
    end

    # padroniza para o restante do fluxo
    payload['tenant'] = resolved_tenant
    payload['__resolved_tenant__'] = resolved_tenant
    payload
  end

  def fetch_jwks!(tenant:)
    url = ENV.fetch('SSO_JWKS_URL')
    uri = URI(url)
    req = Net::HTTP::Get.new(uri)
    req['x-tenant-id'] = tenant # <<<<< chave do problema resolvida
    req['accept'] = 'application/json'

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    res = http.request(req)

    raise "Falha JWKS HTTP #{res.code} em #{url}. Body=#{res.body.to_s[0, 200]}" unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(res.body)
  end

  def find_or_create_user!(email:, name:, external_id:)
    User.find_by(email: email) || begin
      u = User.new(
        email: email,
        name: name,
        password: SecureRandom.hex(16),
        provider: 'crmundi',
        uid: external_id
      )
      u.skip_confirmation! if u.respond_to?(:skip_confirmation!)
      u.confirmed_at ||= Time.current if u.respond_to?(:confirmed_at)
      u.save!
      u
    end
  end

  def find_or_create_account!(raw_tenant)
    tenant = normalize_tenant(raw_tenant)

    # tenta achar
    acc = Account.where("lower(custom_attributes->>'tenant_id') = ?", tenant).first
    return acc if acc

    # cria de forma idempotente
    Account.transaction do
      acc = Account.where("lower(custom_attributes->>'tenant_id') = ?", tenant).first
      return acc if acc

      attrs = {
        name: tenant,
        custom_attributes: { 'tenant_id' => tenant },
        locale: 'pt_BR'
      }

      if Account.column_names.include?('limits')
        default_limits =
          if Account.respond_to?(:DEFAULT_LIMITS) && Account::DEFAULT_LIMITS.is_a?(Hash)
            Account::DEFAULT_LIMITS
          else
            {} # fallback seguro
          end
        attrs[:limits] = default_limits
      end

      acc = Account.create!(attrs)

      # tags (se tiver acts-as-taggable)
      if acc.respond_to?(:tag_list)
        %w[whitelabel crmundi].each { |tag| acc.tag_list.add(tag) }
        acc.save!
      else
        acc.update!(custom_attributes: acc.custom_attributes.merge('tags' => %w[whitelabel crmundi]))
      end

      acc
    end
  rescue ActiveRecord::RecordNotUnique
    Account.where("lower(custom_attributes->>'tenant_id') = lower(?)", tenant).first
  end

  def infer_role_from_payload(payload)
    # fallback se não tiver cw_role (compatibilidade com tokens antigos)
    role = payload['role'].to_s.downcase
    return 'administrator' if role.in?(%w[admin administrator owner super_admin])

    'agent'
  end

  def link_user_to_account_with_role!(user, account, cw_role)
    au = AccountUser.find_or_create_by!(account: account, user: user)
    return au if au.role.to_s == 'administrator' && cw_role != 'administrator'

    au.update!(role: cw_role) if au.role.to_s != cw_role
    au
  end

  def frontend_for_tenant(tenant)
    # Prioridade: FRONTEND_MAP (JSON), depois FRONTEND_URL padrão
    # Ex.: FRONTEND_MAP='{"MTM0001DEV":"http://localhost:3000","MM2":"https://mm2.chatmundi.com"}'
    map_json = ENV['FRONTEND_MAP'].presence
    if map_json
      begin
        map = begin
          JSON.parse(map_json)
        rescue StandardError
          {}
        end
        return map[tenant] if map[tenant].present?
      rescue StandardError
        # ignora parse error e cai para FRONTEND_URL
      end
    end
    ENV.fetch('FRONTEND_URL') # fallback global (um Chatwoot só)
  end
  # Salva o Tenant.name do CRMundi em account.custom_attributes['crmundi_tenant_name'].
  # Chamado a cada SSO para manter o vínculo atualizado sem necessidade de ENV.
  # Nunca propaga erro — uma falha aqui jamais deve interromper o login.
  def upsert_crmundi_tenant_mapping!(account, tenant)
    tenant_name = tenant.to_s.strip
    return if tenant_name.blank?

    attrs = (account.custom_attributes || {}).dup
    # só faz UPDATE se o valor mudou (evita dirty-write desnecessário)
    return if attrs['crmundi_tenant_name'].to_s == tenant_name

    attrs['crmundi_tenant_name'] = tenant_name
    account.update!(custom_attributes: attrs)
    Rails.logger.info("[SSO] CRMundi tenant vinculado na account #{account.id}: #{tenant_name}")
  rescue StandardError => e
    Rails.logger.error("[SSO] Falha ao vincular CRMundi tenant na account #{account&.id}: #{e.class} - #{e.message}")
  end
  def normalize_tenant(raw)
    raw.to_s.strip
  end

  def resolve_tenant_from_request!
    t = request.headers['X-Tenant-Id'].presence ||
        params[:tenant].presence ||
        first_segment_from(params[:next]) ||
        begin
          first_segment_from(URI(request.referer).path)
        rescue StandardError
          nil
        end ||
        begin
          first_segment_from(URI(request.headers['Origin']).path)
        rescue StandardError
          nil
        end

    t = normalize_tenant(t)
    raise 'tenant ausente no request' if t.blank?

    t
  end

  def first_segment_from(path)
    return nil if path.blank?

    path.to_s.split('/').reject(&:blank?).first
  end
end
