# lib/jwks_client.rb
require 'net/http'
require 'json'
require 'jwt'

class JwksClient
  def initialize(url:, ttl: (ENV.fetch('SSO_JWKS_CACHE_TTL', '300').to_i))
    @url = url
    @ttl = ttl
    @cached_at = nil
    @keys = {}
  end

  def key_for(kid)
    refresh_if_needed
    jwk = @keys[kid]
    raise "JWKS key not found for kid=#{kid}" unless jwk

    OpenSSL::PKey::RSA.new(JWT::JWK.import(jwk).key)
  end

  private

  def refresh_if_needed
    return if @cached_at && (Time.now - @cached_at) < @ttl && @keys.any?

    uri = URI(@url)
    body = Net::HTTP.get(uri)
    data = JSON.parse(body)
    @keys = {}
    (data['keys'] || []).each { |k| @keys[k['kid']] = k }
    @cached_at = Time.now
  end
end
