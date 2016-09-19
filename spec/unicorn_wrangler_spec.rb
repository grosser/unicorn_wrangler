require "spec_helper"

describe UnicornWrangler do
  it "has a VERSION" do
    UnicornWrangler::VERSION.should =~ /^[\.\da-z]+$/
  end
end
