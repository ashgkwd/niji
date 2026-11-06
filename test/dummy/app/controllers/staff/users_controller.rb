module Staff
  class UsersController < BaseController
    def index
      @users = User.order(:name)
    end
  end
end
