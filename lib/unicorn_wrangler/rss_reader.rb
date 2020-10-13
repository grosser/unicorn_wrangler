module UnicornWrangler
  class RssReader
    LINUX = RbConfig::CONFIG['host_os'].start_with?('linux')
    PS_CMD = 'ps -o rss= -p %d'.freeze
    VM_RSS = /^VmRSS:\s+(\d+)\s+(\w+)/
    UNITS  = {
      b:  1024**0,
      kb: 1024**1,
      mb: 1024**2,
      gb: 1024**3,
      tb: 1024**4,
    }.freeze

    def initialize(logger:)
      @logger = logger
    end

    # Returns RSS in megabytes; should work on Linux and Mac OS X
    def rss(pid: Process.pid)
      LINUX ? rss_linux(pid) : rss_posix(pid)
    end

    private

    # Fork/exec ps and parse result.
    # Should work on any system with POSIX ps.
    # ~4ms
    # returns kb but we want mb
    def rss_posix(pid)
      `#{PS_CMD % [pid]}`.to_i / 1024
    end

    # Read from /proc/$pid/status.  Linux only.
    # ~100x faster and doesn't incur significant memory cost.
    # file returns variable units, we want mb
    def rss_linux(pid)
      File.read("/proc/#{pid}/status").match(VM_RSS) do |match|
        value, magnitude = match[1].to_i, UNITS.fetch(match[2].downcase.to_sym)

        value * magnitude / UNITS.fetch(:mb)
      end
    rescue
      # If the given pid is dead, file will not be found
      @logger.warn 'Failed to read RSS from /proc, falling back to exec+ps' if @logger
      rss_posix(pid)
    end
  end
end
