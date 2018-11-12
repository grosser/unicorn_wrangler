require_relative '../spec_helper'
require 'unicorn_wrangler/rss_reader'

# Travis is a linux system so we won't test the rss_posix call there,
# but make no assumptions about running locally.
SingleCov.covered! uncovered: ENV['TRAVIS'] ? 1 : 6

describe UnicornWrangler::RssReader do
  describe '.rss_posix' do
    it 'returns an integer of bytes' do
      expect(UnicornWrangler::RssReader.rss_posix).to be < 200 * 1024**2
      expect(UnicornWrangler::RssReader.rss_posix).to be > 5 * 1024**2
    end
  end

  describe '.rss_linux' do
    if UnicornWrangler::RssReader::LINUX || ENV['TRAVIS']
      it 'returns an integer of bytes' do
        expect(UnicornWrangler::RssReader.rss_posix).to be < 200 * 1024**2
        expect(UnicornWrangler::RssReader.rss_posix).to be > 5 * 1024**2
      end

      it 'has approximate parity with rss_posix' do
        # GC shouldn't grow our heap or malloc more than this between calls
        expect(UnicornWrangler::RssReader.rss_linux).to be_within(32 * 1024**2).of(UnicornWrangler::RssReader.rss_posix)
      end
    else
      it 'can not be tested' do
        skip 'platform is non-Linux, can not test /proc RSS reading.'
      end
    end
  end
end
