class Agent < ApplicationRecord
  belongs_to :maker, class_name: "User", optional: true
  has_many :reviews
end
