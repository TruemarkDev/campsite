# frozen_string_literal: true

class TwoFactorChallenge
  SESSION_KEY = :two_factor_challenge
  LIFETIME = 10.minutes
  MAX_ATTEMPTS = 6

  class << self
    def issue!(session, user)
      session[SESSION_KEY] = {
        "attempts" => 0,
        "expires_at" => LIFETIME.from_now.to_i,
        "nonce" => SecureRandom.hex(16),
        "user_id" => user.id,
      }
    end

    def user(session)
      payload = active_payload(session)
      User.find_by(id: payload["user_id"]) if payload
    end

    def record_failure!(session)
      payload = active_payload(session)
      return clear!(session) unless payload

      payload["attempts"] += 1
      payload["attempts"] >= MAX_ATTEMPTS ? clear!(session) : session[SESSION_KEY] = payload
    end

    def consume!(session)
      clear!(session)
    end

    def clear!(session)
      session.delete(SESSION_KEY)
      session.delete(:otp_user_id)
      nil
    end

    private

    def active_payload(session)
      payload = session[SESSION_KEY]
      return unless payload.is_a?(Hash)
      return clear!(session) if payload["expires_at"].to_i <= Time.current.to_i
      return clear!(session) if payload["attempts"].to_i >= MAX_ATTEMPTS

      payload
    end
  end
end
