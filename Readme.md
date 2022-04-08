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
  map_term_to_quit: true, # finish requests before stopping, disables TERM handling on workers
  stats: StatsD.new,
  logger: set.fetch(:logger)
)

# Do additional handlers
UnicornWrangler.handlers << -> (requests, request_time) do
  ... do something / UnicornWrangler.kill_worker ...
end
```

## map_term_to_quit

Unicorn has 2 shutdown modes: SIGTERM = "Kill now" or SIGQUIT = "Wait for requests to finish".
Ideally send the master a SIGQUIT and then let it take care of things and don't use `map_term_to_quit`.

In Kubernetes or Heroku the default shutdown behavior is to send a SIGTERM to all running processes (master and workers).
To make a unicorn app able to still wait for requests `map_term_to_quit`:

 - traps SIGTERM in master and sends a SIGQUIT instead  
 - traps SIGTERM in worker and ignores it  

Ignoring SIGTERM in the worker prevents the worker from getting killed by other means too, like the unicorns internal
`kill_worker` which is called from the master. To kill a worker from inside the worker use `UnicornWrangler.kill_worker`
which will disable the trap unicorn_wrangler sets.

In Kubernetes prefer using this if possible:

```yaml
# allow 3s for new in-flight requests, send QUIT, wait up for graceful shutdown, TERM, wait 2s, KILL
# see https://kubernetes.io/docs/concepts/workloads/pods/pod/#termination-of-pods
lifecycle:
  preStop:
    exec:
      command: ["sh", "-c", "sleep 3 && kill -QUIT 1 && sleep"]
```

## TODO:
 - support other statsd flavors

## Alternatives
 - [gctools](https://github.com/tmm1/gctools) more efficient GC handling, but needs a native extension / is more complex

Author
======
[Michael Grosser](http://grosser.it)<br/>
michael@grosser.it<br/>
License: MIT
