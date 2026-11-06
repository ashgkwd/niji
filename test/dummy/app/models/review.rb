class Review < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :agent, optional: true

  # The reviewer's public display name. Never their email.
  def user_name = user&.name.presence || "Anonymous"
end
