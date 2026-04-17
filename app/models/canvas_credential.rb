class CanvasCredential < ApplicationRecord
  validates :issuer, presence: true, uniqueness: true

  scope :expiring_soon, -> {
    where("expires_at IS NOT NULL AND expires_at < ?", 10.minutes.from_now)
  }
end
