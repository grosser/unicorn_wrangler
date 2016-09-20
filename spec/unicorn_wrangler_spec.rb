require "spec_helper"

SingleCov.covered! uncovered: 2 # uncovered OS specific code

module Unicorn
  class HttpServer
    def process_client(_client)
    end
  end
end

class Stats
  def namespace
    "foobar"
  end
end

describe UnicornWrangler do
  let(:log) { StringIO.new }
  let(:logger) { Logger.new(log) }
  let(:stats) { Stats.new }

  it "has a VERSION" do
    expect(UnicornWrangler::VERSION).to match /^[\.\da-z]+$/
  end

  describe "integration" do
    def server
      log = 'spec/unicorn.log'
      begin
        `cd spec && unicorn -c server.rb -D`
        yield
        sleep 0.1 # sleep for log to flush
        File.read(log)
      ensure
        Process.kill(:TERM, File.read('spec/unicorn.pid').to_i)
        File.unlink(log)
      end
    end

    def get(path='/')
      open("http://localhost:3000#{path}").read
    end

    def with_env(env)
      old = env.keys.map { |k| [k, ENV[k.to_s]] }
      env.each { |k, v| ENV[k.to_s] = v }
      yield
    ensure
      old.each { |k, v| ENV[k.to_s] = v }
    end

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
        max_memory: false,
        logger: logger,
        stats: stats
      )
      expect(log.string.split("\n").size).to eq 1
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

  describe UnicornWrangler::MaxMemoryKiller do
    let(:wrangler) { described_class.new(logger, stats, percent: 0) }

    it "kill on too much memory" do
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
      wrangler.call(250, 100)
    end
  end

  describe UnicornWrangler::RequestTimeKiller do
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

    it "disables GC" do
      GC.enable
      wrangler
      expect(GC.enable).to eq(true) # was disabled
    end

    it "runs GC after too much request time" do
      expect(GC).to receive(:start)

      expect(stats).to receive(:increment)
      expect(stats).to receive(:timing)

      wrangler.call(1, 1000)
      expect(GC.enable).to eq(true) # was disabled again
    end
  end

  describe UnicornWrangler::Killer do
    let(:wrangler) { UnicornWrangler::Killer.new(logger, stats) }

    describe "#kill" do
      it "kills a process" do
        expect(stats).to receive(:increment)
        expect(stats).to receive(:histogram).exactly(3)

        expect(Process).to receive(:kill).with(:QUIT, Process.pid)
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
    end

    describe "#process_client" do
      it "calls wrangler" do
        expect(UnicornWrangler).to receive(:perform_request).and_return(123)
        expect(Foobar.new.process_client(:foo)).to eq(123)
      end
    end
  end
end
