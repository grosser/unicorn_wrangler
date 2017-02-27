# - kills worker when they use too much memory
# - kills worker when they did too many requests (resets leaked memory)
# - runs GC out of band (does not block requests)

require 'benchmark'

module UnicornWrangler
  STATS_NAMESPACE = 'unicorn'

  class << self
    attr_reader :handlers

    # called from unicorn config (usually config/unicorn.rb)
    # high level interface to keep setup consistent / simple
    # set values to false to disable
    def setup(
      kill_after_requests: 10000,
      gc_after_request_time: 10,
      kill_on_too_much_memory: {},
      logger:,
      stats: nil # provide a statsd client with your apps namespace to collect stats
    )
      logger.info "Sending stats to under #{stats.namespace}.#{STATS_NAMESPACE}" if stats
      @handlers = []
      @handlers << RequestKiller.new(logger, stats, kill_after_requests) if kill_after_requests
      @handlers << OutOfMemoryKiller.new(logger, stats, kill_on_too_much_memory) if kill_on_too_much_memory
      @handlers << OutOfBandGC.new(logger, stats, gc_after_request_time) if gc_after_request_time
      Unicorn::HttpServer.prepend UnicornExtension
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
  end

  module UnicornExtension
    def process_client(*)
      UnicornWrangler.perform_request { super }
    end
  end

  class Killer
    def initialize(logger, stats)
      @logger = logger
      @stats = stats
    end

    private

    # Kills the server, thereby resetting @requests / @request_time in the UnicornWrangler
    #
    # Possible issue: kill_worker is not meant to kill the server pid ... might have strange side effects
    def kill(reason, memory, requests, request_time)
      if @stats
        @stats.increment("#{STATS_NAMESPACE}.kill.#{reason}")

        @stats.histogram("#{STATS_NAMESPACE}.kill.memory", memory)
        @stats.histogram("#{STATS_NAMESPACE}.kill.total_requests", requests)
        @stats.histogram("#{STATS_NAMESPACE}.kill.total_request_time", request_time)
      end

      @logger.info "Killing unicorn worker ##{Process.pid} for #{reason}. Requests: #{requests}, Time: #{request_time}, Memory: #{memory}MB"

      Process.kill(:QUIT, Process.pid)
    end

    # expensive, do not run on every request
    def used_memory
      `ps -o rss= -p #{Process.pid}`.to_i / 1024
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
      return unless (memory = used_memory) > @max
      kill :memory, memory, requests, request_time
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
      GC.disable
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
      @logger.info "Garbage collecting: took #{time}ms"
      true
    end
  end
end
