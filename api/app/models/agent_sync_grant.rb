# frozen_string_literal: true

require "digest"

class AgentSyncGrant < ApplicationRecord
  include PublicIdGenerator

  MAX_LIFETIME = 1.hour
  WRITE_SCOPE = "write"
  MENTION_LABELS_SCOPE = "mention_labels"

  belongs_to :note
  belongs_to :organization_membership

  validates :actor_id, :actor_name, :token_digest, :expires_at, presence: true
  validates :actor_id, :actor_name, length: { maximum: 255 }
  validates :scopes, presence: true
  validate :write_scope_is_present
  validate :note_and_membership_share_organization

  scope :active, -> { where(revoked_at: nil, expires_at: Time.current..) }

  def self.issue!(note:, organization_membership:, actor_id:, actor_name:, scopes: [WRITE_SCOPE], expires_in: MAX_LIFETIME)
    lifetime = [expires_in.to_i.seconds, MAX_LIFETIME].min
    raise ArgumentError, "expires_in must be positive" unless lifetime.positive?

    secret = SecureRandom.hex(32)
    grant = create!(
      note: note,
      organization_membership: organization_membership,
      actor_id: actor_id,
      actor_name: actor_name,
      token_digest: digest(secret),
      scopes: scopes,
      expires_at: lifetime.from_now,
    )
    token = verifier.generate({ "grant_id" => grant.public_id, "secret" => secret }, expires_at: grant.expires_at)

    [grant, token]
  end

  def self.authenticate(token:, note_public_id:)
    payload = verifier.verify(token)
    grant = active.includes(note: :member).find_by(public_id: payload.fetch("grant_id"))
    return unless grant
    return unless grant.note.public_id == note_public_id
    return unless grant.scopes.include?(WRITE_SCOPE)
    return unless ActiveSupport::SecurityUtils.secure_compare(grant.token_digest, digest(payload.fetch("secret")))

    grant
  rescue ActiveSupport::MessageVerifier::InvalidSignature, KeyError
    nil
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def active?
    revoked_at.nil? && expires_at.future?
  end

  def mention_labels_scope?
    scopes.include?(MENTION_LABELS_SCOPE)
  end

  def self.digest(secret)
    Digest::SHA256.hexdigest(secret)
  end
  private_class_method :digest

  def self.verifier
    Rails.application.message_verifier(:agent_sync_grant)
  end
  private_class_method :verifier

  private

  def note_and_membership_share_organization
    return unless note && organization_membership
    return if note.organization == organization_membership.organization

    errors.add(:organization_membership, "must belong to the note organization")
  end

  def write_scope_is_present
    errors.add(:scopes, "must include write") unless scopes.is_a?(Array) && scopes.include?(WRITE_SCOPE)
  end
end
