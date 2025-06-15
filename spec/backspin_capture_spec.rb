RSpec.describe "Backspin.capture" do
  context "capture" do
    it "captures stdout and stderr from anything in the block (regardless of how called)"

    it "records to a record file with stdout and stderr, command_type: 'backspin-capturer'"

    it "acts the same as run: record when called with no matching record file"

    it "acts the same as run: verify when called with a matching record file"

    it "uses the same recorder and record interface as Backspin.run"
  end
end