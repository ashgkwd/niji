class Blog < ApplicationRecord
  belongs_to :author, class_name: "User", optional: true
  belongs_to :invited_by, class_name: "User", optional: true
end
