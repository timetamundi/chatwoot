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

    email  = payload['email']
    name   = payload['name'].presence || email
    sub    = payload['sub']
    tenant = payload['account_external_id'].presence || 'CLI-001'
    raise 'email ausente no token' if email.blank?

    user    = find_or_create_user!(email: email, name: name, external_id: sub)
    account = find_or_create_account!(tenant)
    link_user_to_account!(user, account)

    begin
      sign_out_all_scopes
    rescue StandardError
      nil
    end

    sign_in(:user, user)
    # Gera tokens do devise_token_auth (usados pelo SPA)
    auth = user.create_new_auth_token
    user.save!

    target_path = "/app/accounts/#{account.id}/dashboard"

    # Passa tokens e destino pelo fragmento (#) para não irem a logs/servidor
    fragment = Rack::Utils.build_query(
      'uid' => auth['uid'],
      'client' => auth['client'],
      'access-token' => auth['access-token'],
      'token-type' => auth['token-type'],
      'expiry' => auth['expiry'],
      'email' => email,
      'account_id' => account.id,
      'next' => target_path
    )

    redirect_to "/sso/bootstrap##{fragment}"
  rescue StandardError => e
    Rails.logger.error("[SSO] #{e.class}: #{e.message}")
    render plain: "SSO error: #{e.message}", status: :unauthorized
  end

  def bootstrap
    # Renderiza view sem layout; o JS externo em /public faz todo o trabalho
    render 'sso/bootstrap', layout: false
  end

  private

  def verify_with_jwks!(jwt)
    iss = ENV.fetch('SSO_JWT_ISS', 'crmundi')
    aud = ENV.fetch('SSO_JWT_AUD', 'chatmundi')

    header = JWT.decode(jwt, nil, false).last
    kid = header['kid'] or raise 'kid missing in token header'

    jwk = jwks['keys'].find { |k| k['kid'] == kid } or raise "kid #{kid} not found in JWKS"
    public_key = JWT::JWK.import(jwk).public_key

    payload, = JWT.decode(jwt, public_key, true, {
                            algorithm: 'RS256',
                            iss: iss, verify_iss: true,
                            aud: aud, verify_aud: true,
                            leeway: 30
                          })
    payload
  end

  def jwks
    @jwks ||= JSON.parse(Net::HTTP.get(URI(ENV.fetch('SSO_JWKS_URL'))))
  end

  def find_or_create_user!(email:, name:, external_id:)
    User.find_by(email: email) || begin
      u = User.new(email: email, name: name, password: SecureRandom.hex(16), provider: 'crmundi', uid: external_id)
      u.skip_confirmation! if u.respond_to?(:skip_confirmation!)
      u.confirmed_at ||= Time.current if u.respond_to?(:confirmed_at)
      u.save!; u
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
end
