require File.join(File.dirname(__FILE__),"..", "lib", "rails_tidy")
namespace :test do
  desc "validate html in templates"
  task :templates => :environment do
    RailsTidy.path = ENV["FILE"] if ENV.key?("FILE")
    RailsTidy.run
  end
end
