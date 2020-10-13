require_relative '../spec_helper'
require 'unicorn_wrangler/rss_reader'

SingleCov.covered!

describe UnicornWrangler::RssReader do
  shared_examples 'rss reader' do
    it 'returns an integer of bytes' do
      expect(reader.rss).to be < 200
      expect(reader.rss).to be > 1
    end
  end

  let(:log_io) { StringIO.new }
  let(:logger) { Logger.new(log_io) }
  let(:reader) { UnicornWrangler::RssReader.new(logger: logger) }

  describe '.rss' do
    let(:rss) { reader.rss }

    context 'on a linux system' do
      before do
        stub_const('UnicornWrangler::RssReader::LINUX', true)
      end

      it_behaves_like 'rss reader'

      context 'when reading from proc status file' do
        before do
          allow(File).to receive(:read).and_return("VmRSS:	    5748 kB\n")
        end

        it_behaves_like 'rss reader'

        context 'and an error occurs' do
          before do
            allow(File).to receive(:read).and_raise('error')
          end

          it_behaves_like 'rss reader'

          context 'and a logger is not given' do
            let(:logger) { nil }

            it 'does not raise errors' do
              expect { reader.rss }.not_to raise_error
            end
          end
        end
      end
    end

    context 'on a posix system' do
      before do
        stub_const('UnicornWrangler::RssReader::LINUX', false)
      end

      it_behaves_like 'rss reader'
    end
  end
end
