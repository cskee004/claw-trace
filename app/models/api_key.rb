# Manages Bearer token API keys for authenticating agent telemetry ingestion.
# Tokens are generated automatically by has_secure_token; only active keys are accepted.
#
# Columns:
#   token      (string)  auto-generated 24-char alphanumeric Bearer token
#   agent_type (string)  optional label for the agent using this key
#   active     (boolean) false means the key has been revoked
class ApiKey < ApplicationRecord
  has_secure_token :token

  validates :token,  presence: true, uniqueness: true
  validates :active, inclusion: { in: [true, false] }

  scope :active, -> { where(active: true) }

  def self.authenticate(raw_token)
    active.find_by(token: raw_token)
  end
end
