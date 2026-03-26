# frozen_string_literal: true

require "test_helper"
require "rspec/autorun"
require "action_figure/testing/rspec"

# RSpec matchers are tested via RSpec itself, embedded here so the full test
# suite catches regressions without requiring a separate spec runner.

RSpec.describe "ActionFigure::Testing::RSpec matchers" do
  def build_action(&block)
    Class.new do
      include ActionFigure[:jsend]

      define_method(:call, &block)
    end
  end

  it "be_Ok passes for :ok result" do
    action = build_action { Ok(resource: { id: 1 }) }
    expect(action.call).to be_Ok
  end

  it "be_Created passes for :created result" do
    action = build_action { Created(resource: { id: 1 }) }
    expect(action.call).to be_Created
  end

  it "be_Accepted passes for :accepted result" do
    action = build_action { Accepted() }
    expect(action.call).to be_Accepted
  end

  it "be_NoContent passes for :no_content result" do
    action = build_action { NoContent() }
    expect(action.call).to be_NoContent
  end

  it "be_UnprocessableContent passes for :unprocessable_content result" do
    action = build_action { UnprocessableContent(errors: { name: ["can't be blank"] }) }
    expect(action.call).to be_UnprocessableContent
  end

  it "be_NotFound passes for :not_found result" do
    action = build_action { NotFound(errors: { base: ["not found"] }) }
    expect(action.call).to be_NotFound
  end

  it "be_Forbidden passes for :forbidden result" do
    action = build_action { Forbidden(errors: { base: ["not allowed"] }) }
    expect(action.call).to be_Forbidden
  end

  it "be_Ok fails with informative message when status is wrong" do
    action = build_action { Created(resource: { id: 1 }) }
    expect do
      expect(action.call).to be_Ok
    end.to raise_error(RSpec::Expectations::ExpectationNotMetError, /:ok.*:created|:created.*:ok/m)
  end

  it "negated matcher fails with informative message showing actual status" do
    action = build_action { Ok(resource: { id: 1 }) }
    expect do
      expect(action.call).not_to be_Ok
    end.to raise_error(RSpec::Expectations::ExpectationNotMetError, /not to have status :ok/)
  end
end
