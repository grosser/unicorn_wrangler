name = "unicorn_wrangler"
require "./lib/#{name.gsub("-","/")}/version"

Gem::Specification.new name, UnicornWrangler::VERSION do |s|
  s.summary = "Unicorn: out of band GC / restart on max memory bloat / restart after X requests"
  s.authors = ["Michael Grosser"]
  s.email = "michael@grosser.it"
  s.homepage = "https://github.com/grosser/#{name}"
  s.files = `git ls-files lib/ bin/ MIT-LICENSE`.split("\n")
  s.license = "MIT"
  s.required_ruby_version = '>= 2.7.0'
end
