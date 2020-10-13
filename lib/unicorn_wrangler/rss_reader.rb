module UnicornWrangler
  class RssReader
    LINUX = RbConfig::CONFIG['host_os'].start_with?('linux')
    PS_CMD = 'ps -o rss= -p %d'.freeze
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

    # Returns RSS in bytes; should work on Linux and Mac OS X
    def rss(pid: Process.pid)
      LINUX ? rss_linux(pid) : rss_posix(pid)
    end

    def rss_mb(pid: Process.pid)
      rss(pid: pid) / UNITS[:mb]
    end

    private

    # Fork/exec ps and parse result.
    # Should work on any system with POSIX ps.
    # ~4ms
    # returns kb but we want b
    def rss_posix(pid)
      `#{PS_CMD % [pid]}`.to_i * 1024
    end

    # Read from /proc/$pid/status.  Linux only.
    # ~100x faster and doesn't incur significant memory cost.
    def rss_linux(pid)
      if line = File.read("/proc/#{pid}/status").lines.find { |l| l.start_with?('VmRSS') }
        _,c,u = line.chomp.split

        (c.to_i * UNITS[u.downcase.to_sym]).to_i
      else
        @logger.warn 'Failed to parse proc status file, falling back to exec+ps' if @logger
        rss_posix(pid)
      end
    rescue
      @logger.warn 'Failed to read RSS from /proc, falling back to exec+ps' if @logger
      rss_posix(pid)
    end
  end
end
