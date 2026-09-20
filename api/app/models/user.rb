# The HR manager. requirements.md specifies a single persona with full
# visibility of compensation, so there is no role column: a permission
# matrix for roles that do not exist is speculative work.
class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  normalizes :email_address, with: ->(value) { value.strip.downcase }

  validates :email_address,
    presence: true,
    uniqueness: { case_sensitive: false },
    format: { with: URI::MailTo::EMAIL_REGEXP }

  # has_secure_password enforces presence on create but sets no floor on
  # length. 12 is the shortest length worth defending for an account that
  # can read every salary in the organisation.
  validates :password, length: { minimum: 12 }, allow_nil: true
end
