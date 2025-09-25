# app/controllers/sso_controller.rb
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

    payload = verify_with_jwks!(jwt)

    email  = payload['email'] || payload['sub']
    raise 'email/sub ausente no token' if email.blank?

    name   = payload['name'].presence || email.to_s.split('@').first
    sub    = payload['sub']
    # >>> tenant = nome do banco (ex.: MTM0001DEV), vindo do token
    tenant = payload['account_external_id'].presence || payload['tenant'].presence
    raise 'tenant ausente no token (account_external_id/tenant)' if tenant.blank?

    user    = find_or_create_user!(email: email, name: name, external_id: sub)
    account = find_or_create_account!(tenant)
    link_user_to_account!(user, account)

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

    # Caminho padrão do Chatwoot (SEM prefixo de tenant aqui)
    requested_next = params[:next].presence || "/app/accounts/#{account.id}/dashboard"
    requested_next = "/#{requested_next}" unless requested_next.start_with?('/')
    next_path = requested_next  # <- usamos este nome

    fragment = Rack::Utils.build_query(
      'uid' => auth['uid'],
      'client' => auth['client'],
      'access-token' => auth['access-token'],
      'token-type' => auth['token-type'],
      'expiry' => auth['expiry'],
      'email' => email,
      'account_id' => account.id,
      'tenant' => tenant,      # informativo
      'next' => next_path    # <- aqui usamos next_path
    )

    front_base = frontend_for_tenant(tenant)  # mapeia qual Chatwoot abrir
    redirect_to "#{front_base}/sso/bootstrap##{fragment}"
  rescue StandardError => e
    Rails.logger.error("[SSO] #{e.class}: #{e.message}")
    render plain: "SSO error: #{e.message}", status: :unauthorized
  end

  def bootstrap
    render 'sso/bootstrap', layout: false
  end

  private

  def verify_with_jwks!(jwt)
    iss = ENV.fetch('SSO_JWT_ISS', 'crmundi')
    aud = ENV.fetch('SSO_JWT_AUD', 'chatmundi')

    # Lê cabeçalho e payload SEM verificar (só pra extrair kid e tenant)
    unverified_payload, unverified_header = JWT.decode(jwt, nil, false)

    tenant = unverified_payload['account_external_id'].presence ||
             unverified_payload['tenant'].presence ||
             unverified_payload['client_slug'].presence
    raise 'tenant ausente (account_external_id/tenant/client_slug)' if tenant.blank?

    kid = unverified_header['kid'].presence || ENV['SSO_JWT_KID'].presence
    jwks_data = fetch_jwks!(tenant: tenant)

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
      leeway: 30
    )
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

  def find_or_create_account!(ext)
    if Account.column_names.include?('external_id')
      Account.find_by(external_id: ext) || Account.create!(name: ext, external_id: ext, locale: 'pt_BR')
    else
      Account.find_by(name: ext) || Account.create!(name: ext, locale: 'pt_BR')
    end
  end

  def link_user_to_account!(user, account)
    AccountUser.find_or_create_by!(account: account, user: user) { |au| au.role = :administrator }
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
end
