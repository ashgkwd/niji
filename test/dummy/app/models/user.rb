class User < ApplicationRecord
  include Greetable

  PERSONAL_ATTRIBUTES = %w[ name email_address ].freeze

  alias_attribute :email, :email_address

  has_many :reviews

  def name_with_email = "#{name} <#{email_address}>"

  def verified? = true
end
