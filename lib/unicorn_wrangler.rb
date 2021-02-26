# - kills worker when they use too much memory
# - kills worker when they did too many requests (resets leaked memory)
# - runs GC out of band (does not block requests)

require 'benchmark'
require 'unicorn_wrangler/rss_reader'

module UnicornWrangler
  STATS_NAMESPACE = 'unicorn'

  class << self
    attr_reader :handlers, :requests, :request_time
    attr_accessor :sending_myself_term

    # called from unicorn config (usually config/unicorn.rb)
    # high level interface to keep setup consistent / simple
    # set values to false to disable
    def setup(
      kill_after_requests: 10000,
      gc_after_request_time: 10,
      kill_on_too_much_memory: {},
      map_term_to_quit: false,
      logger:,
      stats: nil # provide a statsd client with your apps namespace to collect stats
    )
      logger.info "Sending stats to under #{stats.namespace}.#{STATS_NAMESPACE}" if stats
      @handlers = []
      @handlers << RequestKiller.new(logger, stats, kill_after_requests) if kill_after_requests
      @handlers << OutOfMemoryKiller.new(logger, stats, kill_on_too_much_memory) if kill_on_too_much_memory
      @handlers << OutOfBandGC.new(logger, stats, gc_after_request_time) if gc_after_request_time

      @hooks = {}
      if map_term_to_quit
        # - on heroku & kubernetes all processes get TERM, so we need to trap in master and worker
        # - trapping has to be done in the before_fork since unicorn sets up it's own traps on start
        # - we cannot write to logger inside of a trap, so need to spawn a new Thread
        # - manual test: add a slow route + rails s + curl + pkill -TERM -f 'unicorn master' - request finished?
        @hooks[:before_fork] = -> do
          Signal.trap :TERM do
            Thread.new { logger.info 'master intercepting TERM and sending myself QUIT instead' }
            Process.kill :QUIT, Process.pid
          end
        end

        @hooks[:after_fork] = ->(*) do
          # Signal.trap returns the trap that unicorn set, which is an exit!(0) and calls that when sending myself term
          previous_trap = Signal.trap :TERM do
            if sending_myself_term
              previous_trap.call
            else
              Thread.new { logger.info 'worker intercepting TERM and doing nothing. Wait for master to send QUIT' }
            end
          end
        end
      end

      Unicorn::HttpServer.prepend UnicornExtension
    end

    def kill_worker
      self.sending_myself_term = true # no need to clean up since we are dead after
      Process.kill(:TERM, Process.pid)
    end

    # called from the unicorn server after each request
    def perform_request
      returned = nil
      @requests ||= 0
      @requests += 1
      @request_time ||= 0
      @request_time += Benchmark.realtime { returned = yield }
      returned
    ensure
      @handlers.each { |handler| handler.call(@requests, @request_time) }
    end

    def perform_hook(name)
      if hook = @hooks[name]
        hook.call
      end
    end
  end

  module UnicornExtension
    # call our hook and the users hook since only a single hook can be configured at a time
    # we need to call super so the @<hook> variables get set and unset properly in after_fork to not leak memory
    [:after_fork, :before_fork].each do |hook|
      define_method("#{hook}=") do |value|
        super(->(*args) do
          UnicornWrangler.perform_hook(hook)
          value.call(*args)
        end)
      end
    end

    def process_client(*)
      UnicornWrangler.perform_request { super }
    end

    # run GC after we finished loading out app so forks inherit a clean GC environment
    def build_app!
      super
    ensure
      GC.start
      GC.disable
    end
  end

  class Killer
    def initialize(logger, stats)
      @logger = logger
      @stats = stats
      @rss_reader = RssReader.new(logger: logger)
    end

    private

    # Kills the server, thereby resetting @requests / @request_time in the UnicornWrangler
    #
    # Possible issue: kill_worker is not meant to kill the server pid ... might have strange side effects
    def kill(reason, memory, requests, request_time)
      if @stats
        @stats.increment("#{STATS_NAMESPACE}.killed", tags: ["reason:#{reason}"])

        @stats.distribution("#{STATS_NAMESPACE}.kill.memory", memory)
        @stats.distribution("#{STATS_NAMESPACE}.kill.total_requests", requests)
        @stats.distribution("#{STATS_NAMESPACE}.kill.total_request_time", request_time)
      end

      report_status "Killing", reason, memory, requests, request_time, :warn

      UnicornWrangler.kill_worker
    end

    # RSS memory in MB. Can be expensive, do not run on every request
    def used_memory
      @rss_reader.rss
    end

    def report_status(status, reason, memory, requests, request_time, log_level = :debug)
      @logger.send log_level, "#{status} unicorn worker ##{Process.pid} for #{reason}. Requests: #{requests}, Time: #{request_time}, Memory: #{memory}MB"
    end
  end

  class OutOfMemoryKiller < Killer
    def initialize(logger, stats, max: 20, check_every: 250)
      super(logger, stats)
      @max = max
      @check_every = check_every
      @logger.info "Killing workers when using more than #{@max}MB"
    end

    def call(requests, request_time)
      return unless (requests % @check_every).zero? # avoid overhead of checking memory too often
      memory = used_memory
      if memory > @max
        kill :memory, memory, requests, request_time
      else
        @stats.distribution("#{STATS_NAMESPACE}.keep.memory", memory) if @stats
        report_status "Keeping", :memory, memory, requests, request_time
      end
    end
  end

  class RequestKiller < Killer
    def initialize(logger, stats, max_requests)
      super(logger, stats)
      @max_requests = max_requests
      @logger.info "Killing workers after #{@max_requests} requests"
    end

    def call(requests, request_time)
      kill(:requests, used_memory, requests, request_time) if requests >= @max_requests
    end
  end

  # Do not run GC inside of requests, but only after a certain time spent in requests
  #
  # Alternative:
  # https://github.com/tmm1/gctools
  # which is more sophisticated and will result in less time spent GCing and less overall memory needed
  class OutOfBandGC
    def initialize(logger, stats, max_request_time)
      @logger = logger
      @stats = stats
      @max_request_time = max_request_time
      @logger.info "Garbage collecting after #{@max_request_time}s of request processing time"
      @gc_ran_at = 0
    end

    def call(_requests, request_time)
      time_since_last_gc = request_time - @gc_ran_at
      return unless time_since_last_gc >= @max_request_time
      @gc_ran_at = request_time

      time = Benchmark.realtime do
        GC.enable
        GC.start
        GC.disable
      end

      time = (time * 1000).round # s -> ms
      if @stats
        @stats.increment("#{STATS_NAMESPACE}.oobgc.runs")
        @stats.timing("#{STATS_NAMESPACE}.oobgc.time", time)
      end
      @logger.debug "Garbage collecting: took #{time}ms"
      true
    end
  end
end
