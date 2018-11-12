module UnicornWrangler
  class RssReader
    LINUX = RbConfig::CONFIG['host_os'].start_with?('linux')
    PS_CMD = "ps -o rss= -p %d".freeze
    UNITS  = {
      b:  1024**0,
      kb: 1024**1,
      mb: 1024**2,
      gb: 1024**3,
      tb: 1024**4,
    }.freeze

    class << self
      # Returns RSS in bytes; should work on Linux and Mac OS X
      def rss(pid=Process.pid)
        LINUX ? rss_linux(pid) : rss_posix(pid)
      end

      # Fork/exec ps and parse result.
      # Should work on any system with POSIX ps.
      # ~4ms
      def rss_posix(pid=Process.pid)
        `#{PS_CMD % [pid]}`.to_i * 1024
      end

      # Read from /proc/$pid/status.  Linux only.
      # ~100x faster and doesn't incur significant memory cost.
      def rss_linux(pid=Process.pid)
        File.open("/proc/#{pid}/status") do |file|
          file.each_line do |line|
            if line[/^VmRSS/]
              _,c,u = line.split
              return (c.to_i * UNITS[u.downcase.to_sym]).to_i
            end
          end
        end
      end
    end
  end
end
