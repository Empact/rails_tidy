require File.join(File.dirname(__FILE__),"..", "lib", "rails_tidy")

desc "validate html in templates"
task :test_templates => :environment do
  RailsTidy.path = ENV["FILE"] if ENV.key?("FILE")
  RailsTidy.run
end
