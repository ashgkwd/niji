module Greetable
  extend ActiveSupport::Concern

  def greeting_name = name.presence || "there"
end
