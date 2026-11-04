# frozen_string_literal: true

module Campsite
  module SmtpSettings
    AUTHENTICATIONS = %w[none plain login cram_md5].freeze
    BOOLEANS = { "false" => false, "true" => true }.freeze

    def self.build(environment: ENV, credentials: {})
      authentication = environment.fetch("SMTP_AUTHENTICATION", "plain")
      unless AUTHENTICATIONS.include?(authentication)
        raise ArgumentError, "SMTP_AUTHENTICATION must be one of: #{AUTHENTICATIONS.join(", ")}"
      end

      starttls_value = environment.fetch("SMTP_STARTTLS", "true")
      enable_starttls_auto = BOOLEANS.fetch(starttls_value) do
        raise ArgumentError, "SMTP_STARTTLS must be true or false"
      end

      # Rails defaults both timeouts to 5s. Stalwart runs the message through
      # spam analysis inside the DATA phase and has been observed taking 12s to
      # answer, which surfaces as Net::ReadTimeout mid-delivery even though the
      # message is queued and delivered. Devise sends the confirmation inline
      # during signup, so that timeout 500s the request.
      settings = {
        address: environment.fetch("SMTP_ADDRESS", "smtp.postmarkapp.com"),
        port: Integer(environment.fetch("SMTP_PORT", "587"), 10),
        domain: environment.fetch("SMTP_DOMAIN", "tokdio.com"),
        enable_starttls_auto: enable_starttls_auto,
        open_timeout: Integer(environment.fetch("SMTP_OPEN_TIMEOUT", "5"), 10),
        read_timeout: Integer(environment.fetch("SMTP_READ_TIMEOUT", "5"), 10),
      }

      return settings if authentication == "none"

      settings.merge(
        user_name: environment["SMTP_USER"] || credentials.dig(:smtp, :user),
        password: environment["SMTP_PASSWORD"] || credentials.dig(:smtp, :password),
        authentication: authentication,
      )
    end
  end
end
