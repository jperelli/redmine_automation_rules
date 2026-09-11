require 'net/http'
require 'openssl'

module RedmineAutomationRules
  # Delivers webhook payloads. Like Periodic-Task's web scheduler the HTTP
  # request runs in a background thread wrapped in the Rails executor so the
  # user's request is not slowed down; +synchronous+ makes it run inline
  # (tests, rake). The result of each delivery is only logged.
  module Webhook
    SIGNATURE_HEADER = 'X-Automation-Rules-Signature'.freeze
    SECRET_HEADER = 'X-Automation-Rules-Secret'.freeze
    TIMEOUT = 10

    class << self
      attr_accessor :synchronous, :transport

      def deliver(url, payload, secret: nil, headers: {})
        body = payload.to_json
        if synchronous
          post(url, body, secret, headers)
        else
          Thread.new do
            Rails.application.executor.wrap { post(url, body, secret, headers) }
          end
        end
      end

      def valid_url?(url)
        uri = URI.parse(url.to_s)
        uri.is_a?(URI::HTTP) && uri.host.present?
      rescue URI::InvalidURIError
        false
      end

      def signature(secret, body)
        OpenSSL::HMAC.hexdigest('SHA256', secret.to_s, body)
      end

      private

      def post(url, body, secret, headers)
        uri = URI.parse(url)
        request = Net::HTTP::Post.new(uri)
        request['Content-Type'] = 'application/json'
        request['User-Agent'] = "Redmine Automation Rules/#{RedmineAutomationRules::VERSION}"
        headers.each { |name, value| request[name] = value }
        if secret.present?
          request[SECRET_HEADER] = secret
          request[SIGNATURE_HEADER] = "sha256=#{signature(secret, body)}"
        end
        request.body = body
        response = (transport || default_transport).call(uri, request)
        Rails.logger.info("[automation_rules] webhook #{uri.host}: #{response.code}")
        response
      rescue StandardError => e
        Rails.logger.error("[automation_rules] webhook #{url}: #{e.class}: #{e.message}")
        nil
      end

      def default_transport
        lambda do |uri, request|
          Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == 'https',
                                              open_timeout: TIMEOUT, read_timeout: TIMEOUT) do |http|
            http.request(request)
          end
        end
      end
    end
  end
end
