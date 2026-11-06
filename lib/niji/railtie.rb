# frozen_string_literal: true

module Niji
  class Railtie < Rails::Railtie
    rake_tasks do
      load File.expand_path("../tasks/niji.rake", __dir__)
    end
  end
end
