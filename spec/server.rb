require 'datadog/statsd'
require 'unicorn_wrangler'

pid 'unicorn.pid'
listen 3000
log = 'unicorn.log'
stdout_path log # make puts debugging visible
log = Logger.new('unicorn.log')
logger log

stats = Datadog::Statsd.new
killer = ENV['TEST_KILLER']

UnicornWrangler.setup(
  gc_after_request_time: 0.1,
  kill_after_requests: killer == 'requests' && 5,
  kill_on_too_much_memory: killer == 'memory' && {max: 0, check_every: 3},
  stats: stats,
  logger: log
)

UnicornWrangler.handlers << -> (a,b) { log.info "Custom handler" }
