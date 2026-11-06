class MakerMailer < ApplicationMailer
  def daily_reviews_digest(maker, spotlight_agent)
    @maker = maker
    @spotlight_agent = spotlight_agent
    mail to: maker.email_address, subject: "Reviews waiting for you"
  end
end
