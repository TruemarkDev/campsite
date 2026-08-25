# frozen_string_literal: true

require "ipaddr"
require "net/http"
require "openssl"
require "resolv"
require "timeout"

module Oauth
  module Cimd
    class Fetcher
      Response = Data.define(:body, :headers)

      MAX_BODY_BYTES = 5 * 1024
      TOTAL_TIMEOUT = 5.seconds
      OPEN_TIMEOUT = 2.seconds
      READ_TIMEOUT = 3.seconds
      SPECIAL_USE_NETWORKS = [
        "0.0.0.0/8",
        "10.0.0.0/8",
        "100.64.0.0/10",
        "127.0.0.0/8",
        "169.254.0.0/16",
        "172.16.0.0/12",
        "192.0.0.0/24",
        "192.0.2.0/24",
        "192.31.196.0/24",
        "192.52.193.0/24",
        "192.88.99.0/24",
        "192.168.0.0/16",
        "192.175.48.0/24",
        "198.18.0.0/15",
        "198.51.100.0/24",
        "203.0.113.0/24",
        "224.0.0.0/4",
        "240.0.0.0/4",
        "::/128",
        "::1/128",
        "::ffff:0:0/96",
        "64:ff9b::/96",
        "64:ff9b:1::/48",
        "100::/64",
        "100:0:0:1::/64",
        "2001::/23",
        "2001:db8::/32",
        "2002::/16",
        "2620:4f:8000::/48",
        "3fff::/20",
        "5f00::/16",
        "fc00::/7",
        "fe80::/10",
        "ff00::/8",
      ].map { |network| IPAddr.new(network) }.freeze

      def initialize(
        resolver: ->(host) { Resolv.getaddresses(host) },
        connection_factory: method(:build_connection)
      )
        @resolver = resolver
        @connection_factory = connection_factory
      end

      def fetch!(uri)
        addresses = @resolver.call(uri.host).uniq
        raise FetchError if addresses.empty?

        parsed_addresses = addresses.map { |address| IPAddr.new(address) }
        raise PolicyError unless parsed_addresses.all? { |address| public_address?(address) }

        connection = @connection_factory.call(uri, addresses.first)
        request = Net::HTTP::Get.new(uri.request_uri, {
          "Accept" => "application/json, application/*+json",
          "User-Agent" => "Campsite-CIMD/1.0",
        })

        response = nil
        body = +""
        Timeout.timeout(TOTAL_TIMEOUT) do
          connection.request(request) do |http_response|
            response = http_response
            http_response.read_body do |chunk|
              raise FetchError if body.bytesize + chunk.bytesize > MAX_BODY_BYTES

              body << chunk
            end
          end
        end

        raise PolicyError if response.is_a?(Net::HTTPRedirection)
        raise FetchError unless response.is_a?(Net::HTTPOK)
        raise FetchError unless json_content_type?(response["Content-Type"])

        Response.new(body: body, headers: response.to_hash)
      rescue FetchError
        raise
      rescue IPAddr::InvalidAddressError,
             OpenSSL::SSL::SSLError,
             Resolv::ResolvError,
             SocketError,
             SystemCallError,
             Timeout::Error
        raise FetchError
      end

      private

      def public_address?(address)
        SPECIAL_USE_NETWORKS.none? { |network| network.include?(address) }
      end

      def json_content_type?(content_type)
        media_type = content_type.to_s.split(";", 2).first.to_s.strip.downcase
        media_type == "application/json" ||
          (media_type.start_with?("application/") && media_type.end_with?("+json") && !media_type.match?(/[[:space:],]/))
      end

      def build_connection(uri, address)
        connection = Net::HTTP.new(uri.host, uri.port)
        connection.ipaddr = address
        connection.use_ssl = true
        connection.verify_mode = OpenSSL::SSL::VERIFY_PEER
        connection.open_timeout = OPEN_TIMEOUT
        connection.read_timeout = READ_TIMEOUT
        connection.write_timeout = OPEN_TIMEOUT
        connection
      end
    end
  end
end
