Unicorn helpers for: 
 - out of band GC 
 - restart on max memory bloat
 - restart after X requests
 - not killing active requests when stopping (map TERM into QUIT see [heroku docs](https://devcenter.heroku.com/articles/rails-unicorn#signal-handling))

Install
=======

```Bash
gem install unicorn_wrangler
```

Usage
=====

Each handler can be  deactivated by setting it to `false`.

```Ruby
# unicorn.rb
require 'unicorn_wrangler'
UnicornWrangler.setup(
  kill_after_requests: 10000,
  kill_on_too_much_memory: {
    max: 70, # MB 
    check_every: 250 # requests
  },
  gc_after_request_time: 10, # seconds
  map_term_to_quit: true, # finish requests before stopping
  stats: StatsD.new,
  logger: set.fetch(:logger)
)

# Do additional handlers
UnicornWrangler.handlers << -> (requests, request_time) do
  ... do something ...
end
```

## TODO:
 - support other statsd flavors

## Alternatives
 - [gctools](https://github.com/tmm1/gctools) more efficient GC handling, but needs a native extension / is more complex

Author
======
[Michael Grosser](http://grosser.it)<br/>
michael@grosser.it<br/>
License: MIT<br/>
[![Build Status](https://travis-ci.org/grosser/unicorn_wrangler.png)](https://travis-ci.org/grosser/unicorn_wrangler)
