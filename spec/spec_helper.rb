require "bundler/setup"
require "unicorn_wrangler/version"
require "unicorn_wrangler"

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :should }
  config.mock_with(:rspec) { |c| c.syntax = :should }
end
