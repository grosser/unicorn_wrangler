Unicorn: out of band GC / restart on max memory bloat / restart after X requests

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
  gc_after_request_time: 10,
  max_memory: {percent: 70, check_ever: 250},
  stats: StatsD.new,
  logger: set.fetch(:logger)
)

# Do additional handlers
UnicornWrangler.handlers << -> (requests, request_time) do
  ... do something and return nil/false ...
end
```

## TODO:
 - kill workers instead of the whole server
 - support other statsd flavors
 - request time reset behavior and statsd logging makes little sense ... only reset internally and do math to figure out total 

## Alternatives
 - [gctools](https://github.com/tmm1/gctools) more efficient GC handling, but needs a native extension / is more complex

Author
======
[Michael Grosser](http://grosser.it)<br/>
michael@grosser.it<br/>
License: MIT<br/>
[![Build Status](https://travis-ci.org/grosser/unicorn_wrangler.png)](https://travis-ci.org/grosser/unicorn_wrangler)
