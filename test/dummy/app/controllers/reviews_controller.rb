class ReviewsController < ApplicationController
  allow_unauthenticated_access

  def index
    @reviews = Review.includes(:user)
  end
end
