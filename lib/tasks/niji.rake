# frozen_string_literal: true

namespace :niji do
  desc "Fail when a person's name or email can reach another person's screen unreviewed (ALL=1 lists every read)"
  task check: :environment do
    report = Niji::Report.new(Niji.check, all: ENV["ALL"].present?)
    puts report
    exit 1 unless report.success?
  end
end
