require "bundler/setup"

require "single_cov"
SingleCov.setup :rspec

require "unicorn_wrangler/version"
require "unicorn_wrangler"
require "logger"
require "open-uri"
require "unicorn"
require "rack"
