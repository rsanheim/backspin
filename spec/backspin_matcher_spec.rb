# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Backspin matcher contract" do
  around do |example|
    with_tmp_dir_for_backspin(&example)
  end

  it "supports proc matchers for command runs" do
    Backspin.run(["echo", "hello"], name: "proc_matcher", mode: :record)

    matcher = lambda { |recorded, actual|
      recorded["stdout"].start_with?("hello") && actual["stdout"].start_with?("hello")
    }

    result = Backspin.run(["echo", "hello"], name: "proc_matcher", matcher: matcher)

    expect(result).to be_verified
  end

  it "supports field-specific matchers for capture" do
    Backspin.capture("field_matcher") do
      puts "Value: 123"
    end

    matcher = {
      stdout: ->(recorded, actual) {
        recorded.gsub(/\d+/, "[NUM]") == actual.gsub(/\d+/, "[NUM]")
      }
    }

    result = Backspin.capture("field_matcher", matcher: matcher) do
      puts "Value: 999"
    end

    expect(result).to be_verified
  end

  it "supports :all matchers alongside field matchers" do
    Backspin.run(["echo", "status"], name: "all_matcher", mode: :record)

    matcher = {
      all: ->(recorded, actual) { recorded["status"] == actual["status"] },
      stdout: ->(recorded, actual) { recorded == actual }
    }

    result = Backspin.run(["echo", "status"], name: "all_matcher", matcher: matcher)

    expect(result).to be_verified
  end
end
