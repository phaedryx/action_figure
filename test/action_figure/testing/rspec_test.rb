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

  it "have_action_json passes when json matches subset" do
    action = build_action { Ok(resource: { name: "Tad" }) }

    expect(action.call).to have_action_json(status: "success", data: { name: "Tad" })
  end

  it "have_action_json nests a_hash_including for partial data assertions" do
    action = build_action { Ok(resource: { name: "Tad", id: 1 }) }

    expect(action.call).to have_action_json(
      status: "success",
      data: a_hash_including(name: "Tad")
    )
  end

  it "have_action_json fails with a descriptive message when shape differs" do
    action = build_action { Ok(resource: {}) }

    expect do
      expect(action.call).to have_action_json(status: "fail")
    end.to raise_error(RSpec::Expectations::ExpectationNotMetError)
  end

  def build_validated_action(&schema)
    Class.new do
      include ActionFigure[:jsend]

      params_schema(&schema)

      def call(params:) = Ok(resource: params)
    end
  end

  it "accept_params passes when the contract accepts the params" do
    action = build_validated_action { required(:email).filled(:string) }

    expect(action).to accept_params(email: "jane@example.com")
  end

  it "accept_params can be negated for invalid params" do
    action = build_validated_action { required(:email).filled(:string) }

    expect(action).not_to accept_params(email: "")
  end

  it "reject_params passes when the contract rejects the params" do
    action = build_validated_action { required(:email).filled(:string) }

    expect(action).to reject_params(email: "")
  end

  it "reject_params scoped with_error_on passes when that field errors" do
    action = build_validated_action do
      required(:email).filled(:string)
      required(:name).filled(:string)
    end

    expect(action).to reject_params(name: "Jane").with_error_on(:email)
  end

  it "reject_params scoped with_error_on fails when a different field errors" do
    action = build_validated_action do
      required(:email).filled(:string)
      required(:name).filled(:string)
    end

    # email is missing (so :email errors), but we assert the error is on :name
    expect do
      expect(action).to reject_params(name: "Jane").with_error_on(:name)
    end.to raise_error(RSpec::Expectations::ExpectationNotMetError, /:name/)
  end

  it "be_* fails clearly when given a non-result value" do
    expect do
      expect("nope").to be_Ok
    end.to raise_error(RSpec::Expectations::ExpectationNotMetError, /result hash/)
  end

  it "contract matchers fail clearly for actions without a schema" do
    action = build_action { Ok(resource: {}) }

    expect do
      expect(action).to accept_params({})
    end.to raise_error(ArgumentError, /params_schema/)
  end
end
