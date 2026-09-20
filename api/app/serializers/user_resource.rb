# Deliberately minimal. There is one role, so there is nothing to expose
# beyond identity, and password_digest must never leave the process.
class UserResource
  include Alba::Resource

  attributes :id, :email_address
end
