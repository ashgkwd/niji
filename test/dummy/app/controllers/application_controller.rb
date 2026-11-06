class ApplicationController < ActionController::Base
  # Stands in for the class method of Rails' authentication generator.
  def self.allow_unauthenticated_access(**) = nil

  helper_method :admin?

  private

  def admin? = Current.user&.name == "admin"

  def require_admin
    head :forbidden unless admin?
  end
end
