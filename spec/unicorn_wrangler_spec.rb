require "spec_helper"

SingleCov.covered!

module Unicorn
  class HttpServer
    def process_client(_client)
    end

    def build_app!
    end
  end
end

class Stats
  def namespace
    "foobar"
  end
end

module UnicornWrangler::Signal
  class << self
    def trap(_sig, &block)
      (@trapped ||= []) << block
    end

    def trapped
      @trapped
    end
  end
end

describe UnicornWrangler do
  let(:log) { StringIO.new }
  let(:logger) { Logger.new(log) }
  let(:stats) { Stats.new }

  before do
    UnicornWrangler.instance_variable_set(:@hooks, nil)
    UnicornWrangler.instance_variable_set(:@handlers, nil)
  end

  it "has a VERSION" do
    expect(UnicornWrangler::VERSION).to match /^[\.\da-z]+$/
  end

  describe "integration" do
    def server
      log = 'spec/unicorn.log'
      `cd spec && unicorn -c server.rb -D --no-default-middleware`
      yield
      sleep 0.1 # sleep for log to flush
      File.read(log)
    rescue
      puts "LOGS: #{File.read(log)}" if File.exist?(log)
      raise
    ensure
      Process.kill(:TERM, master_pid)
      File.unlink(log)
    end

    # don't use open.read, it retries
    def get(path='/')
      `curl -sf http://localhost:3234#{path}`
    end

    def with_env(env)
      old = env.keys.map { |k| [k, ENV[k.to_s]] }
      env.each { |k, v| ENV[k.to_s] = v }
      yield
    ensure
      old.each { |k, v| ENV[k.to_s] = v }
    end

    def child_pids(pid)
      pipe = IO.popen("ps -ef | grep #{pid}")
      pipe.readlines.map do |line|
        parts = line.strip.split(/\s+/)
        parts[1].to_i if parts[2] == pid.to_s and parts[1] != pipe.pid.to_s
      end.compact
    end

    let(:master_pid) { Integer(File.read('spec/unicorn.pid')) }

    it "calls custom handler" do
      log = server { expect(get).to include("Foo") }
      expect(log).to include("Custom handler")
    end

    it "kills when reaching max memory" do
      with_env 'TEST_KILLER' => 'memory' do
        log = server { 3.times { get } }
        expect(log).to match /Killing unicorn worker.*for memory/
      end
    end

    it "kills when reaching max requests" do
      with_env 'TEST_KILLER' => 'requests' do
        log = server { 5.times { get } }
        expect(log).to match /Killing unicorn worker.*for requests/
      end
    end

    it "runs GC reaching max request time" do
      log = server { get '/slow' }
      expect(log).to include "Garbage collecting: took"
    end

    it "runs custom before hook" do
      with_env BEFORE_HOOK: 'true' do
        log = server { get }
        expect(log).to include "GOT BEFORE_HOOK"
      end
    end

    it "runs custom hook even when we hijack the hook" do
      with_env BEFORE_HOOK: 'true', MAP_TERM_TO_QUIT: 'true' do
        log = server { get }
        expect(log).to include "GOT BEFORE_HOOK"
      end
    end

    it "finishes requests when master receives TERM" do
      with_env MAP_TERM_TO_QUIT: 'true' do
        client = nil
        # server stays open for 0.1s and then sends itself TERM, but client request takes 0.5s
        server = Thread.new { server { client = Thread.new { get '/vslow' }} }
        log = server.value
        client.join
        expect(log).to include "worker=0 ready"
      end
    end

    it "finishes requests when worker receives TERM" do
      with_env MAP_TERM_TO_QUIT: 'true' do
        log = server do
          client = Thread.new { get('/vslow') }
          sleep 0.2 # let worker boot ... request will take 0.5s so it still runs after
          worker = child_pids(master_pid).first || raise("No child found")
          Process.kill(:TERM, worker) # send term to worker which it should ignore
          expect(client.value).to eq "Foo #{worker}"
        end
        expect(log).to include "worker=0 ready"
      end
    end
  end

  describe ".setup" do
    it "adds a hook to unicorns server" do
      UnicornWrangler.setup(logger: logger, stats: stats)
      expect(log.string.split("\n").size).to eq 4
    end

    it "can disable handlers" do
      UnicornWrangler.setup(
        kill_after_requests: false,
        gc_after_request_time: false,
        kill_on_too_much_memory: false,
        logger: logger,
        stats: stats
      )
      expect(log.string.split("\n").size).to eq 1
    end

    it "can run without stats" do
      UnicornWrangler.setup(
        kill_after_requests: false,
        gc_after_request_time: false,
        kill_on_too_much_memory: false,
        logger: logger
      )
      expect(log.string.split("\n").size).to eq 0
    end

    it "can add additional before hook" do
      UnicornWrangler.setup(logger: logger, map_term_to_quit: true)

      expect(Process).to receive(:kill)
      expect(logger).to receive(:info).exactly(2)
      UnicornWrangler.perform_hook :before_fork
      UnicornWrangler.perform_hook :after_fork
      UnicornWrangler::Signal.trapped.each { |h| h.call 1, 2 }
      sleep 0.1 # let logger thread finish
    end
  end

  describe ".perform_request" do
    it "calls all handlers" do
      called = []
      UnicornWrangler.instance_variable_set(:@handlers, [1]) # as if setup was run
      UnicornWrangler.handlers.replace [-> (*args) { called << args }]
      expect(UnicornWrangler.perform_request { 123 }).to eq(123)
      expect(called.first.first).to eq(1)
    end
  end

  describe ".perform_before_fork" do
    it "does nothing when nothing was configured" do
      UnicornWrangler.instance_variable_set(:@hooks, {})
      UnicornWrangler.perform_hook :before_fork
    end

    it "performs" do
      called = []
      UnicornWrangler.instance_variable_set(:@hooks, before_fork: -> { called << 1 })
      UnicornWrangler.perform_hook :before_fork
      expect(called).to eq([1])
    end
  end

  describe UnicornWrangler::OutOfMemoryKiller do
    let(:wrangler) { described_class.new(logger, stats, max: 0) }

    it "kill on too little free memory" do
      expect(wrangler).to receive(:kill)
      wrangler.call(250, 100)
    end

    it "does not kill/check on every request" do
      expect(wrangler).to_not receive(:kill)
      wrangler.call(1, 100)
    end

    it "does not kill on too little memory" do
      expect(wrangler).to receive(:used_memory).and_return(0)
      expect(wrangler).to_not receive(:kill)
      expect(stats).to receive(:histogram)
      wrangler.call(250, 100)
    end

    it "does not fail without stats" do
      wrangler = described_class.new(logger, nil, max: 0)
      expect(wrangler).to receive(:used_memory).and_return(0)
      wrangler.call(250, 100)
    end
  end

  describe UnicornWrangler::RequestKiller do
    let(:wrangler) { described_class.new(logger, stats, 1000) }

    it "kills on too many requests" do
      expect(wrangler).to receive(:kill)
      wrangler.call(1000, 100)
    end

    it "does not kill on too few requests" do
      expect(wrangler).to_not receive(:kill)
      wrangler.call(999, 100)
    end
  end

  describe UnicornWrangler::OutOfBandGC do
    let(:wrangler) { described_class.new(logger, stats, 1000) }

    it "runs GC after too much request time" do
      expect(GC).to receive(:start)

      expect(stats).to receive(:increment)
      expect(stats).to receive(:timing)

      wrangler.call(1, 1000)
      expect(GC.enable).to eq(true) # was disabled again
    end

    it "does not run GC after too little request time" do
      expect(GC).to_not receive(:start)
      wrangler.call(1, 10)
    end

    it "works without stats" do
      wrangler.instance_variable_set(:@stats, nil)
      wrangler.call(1, 1000)
    end
  end

  describe UnicornWrangler::Killer do
    let(:wrangler) { UnicornWrangler::Killer.new(logger, stats) }

    describe "#kill" do
      it "kills a process" do
        expect(stats).to receive(:increment)
        expect(stats).to receive(:histogram).exactly(3)

        expect(Process).to receive(:kill).with(:TERM, Process.pid)
        wrangler.send(:kill, :foobar, 1, 2, 3)
      end

      it "works without stats" do
        wrangler.instance_variable_set(:@stats, nil)
        expect(Process).to receive(:kill).with(:TERM, Process.pid)
        wrangler.send(:kill, :foobar, 1, 2, 3)
      end
    end
  end

  describe UnicornWrangler::UnicornExtension do
    class Foobar
      prepend UnicornWrangler::UnicornExtension # what setup does
      def process_client(client)
        123
      end

      def build_app!
        123
      end

      def before_fork=(x)
        @before_fork = x
      end

      def before_fork
        @before_fork.call(1, 2)
      end
    end

    describe "#process_client" do
      it "calls wrangler" do
        expect(UnicornWrangler).to receive(:perform_request).and_return(123)
        expect(Foobar.new.process_client(:foo)).to eq(123)
      end
    end

    describe "#build_app!" do
      it "disables GC" do
        GC.enable
        expect(GC).to receive(:start)
        expect(Foobar.new.build_app!).to eq 123
        expect(GC.enable).to eq true # was off ?
      end
    end

    describe "hooks" do
      it "calls original and ours" do
        called = []
        UnicornWrangler.instance_variable_set(:@hooks, before_fork: ->(*){ called << 1 })
        server = Foobar.new
        server.before_fork = ->(*) { called << 2 }
        server.before_fork
        expect(called).to eq [1, 2]
      end
    end
  end
end
