# frozen_string_literal: true

require "digest"

module Oauth
  module Cimd
    class Resolver
      def initialize(cache: Rails.cache, fetcher: Fetcher.new)
        @cache = cache
        @fetcher = fetcher
      end

      def resolve!(client_id)
        uri = ClientId.parse!(client_id)
        metadata = cached_metadata(client_id)
        return persist!(metadata) if metadata

        Cimd.instrument(:cache_miss, host: uri.host)
        response = @fetcher.fetch!(uri)
        metadata = Metadata.parse!(response.body, expected_client_id: client_id)
        cache_metadata(metadata, response.headers)
        Cimd.instrument(:resolved, host: uri.host)
        persist!(metadata)
      rescue InvalidClientId
        Cimd.instrument(:invalid_client_id)
        raise
      rescue PolicyError
        Cimd.instrument(:policy_rejected, host: uri&.host)
        raise
      rescue FetchError
        Cimd.instrument(:fetch_failed, host: uri&.host)
        raise
      rescue InvalidMetadata
        Cimd.instrument(:invalid_metadata, host: uri&.host)
        raise
      end

      private

      def cached_metadata(client_id)
        cached = @cache.read(cache_key(client_id))
        return unless cached

        Cimd.instrument(:cache_hit, host: URI.parse(client_id).host)
        Metadata.new(cached, expected_client_id: client_id)
      rescue InvalidMetadata
        @cache.delete(cache_key(client_id))
        nil
      end

      def cache_metadata(metadata, headers)
        ttl = CachePolicy.ttl(headers)
        return unless ttl

        @cache.write(cache_key(metadata.client_id), metadata.to_cache, expires_in: ttl)
      end

      def cache_key(client_id)
        "#{CACHE_NAMESPACE}:#{Digest::SHA256.hexdigest(client_id)}"
      end

      def persist!(metadata)
        application = OauthApplication.find_or_initialize_by(uid: metadata.client_id)
        raise InvalidMetadata if application.persisted? && !application.mcp_cimd?

        application.assign_attributes(
          name: metadata.client_name,
          redirect_uri: metadata.redirect_uris,
          scopes: DEFAULT_SCOPES,
          confidential: false,
          provider: :mcp_cimd,
        )
        application.save!
        application
      rescue ActiveRecord::RecordNotUnique
        retry
      end
    end
  end
end
