# frozen_string_literal: true

require "rspec/matchers"

module ActionFigure
  module Testing
    # RSpec custom matchers for ActionFigure response results.
    #
    # Require in your spec_helper.rb to get be_Ok, be_Created, etc.:
    #
    #   require 'action_figure/testing/rspec'
    #
    #   RSpec.describe Users::Create do
    #     it "returns ok" do
    #       expect(Users::Create.call(params: ...)).to be_Ok
    #       expect(Users::Create.call(params: ...)).to have_action_json(status: "success")
    #     end
    #   end
    module RSpec
      MATCHERS = {
        Ok: :ok,
        Created: :created,
        Accepted: :accepted,
        NoContent: :no_content,
        UnprocessableContent: :unprocessable_content,
        NotFound: :not_found,
        Forbidden: :forbidden,
        Conflict: :conflict,
        PaymentRequired: :payment_required
      }.freeze

      MATCHERS.each do |name, status|
        ::RSpec::Matchers.define :"be_#{name}" do
          match { |result| result[:status] == status }
          failure_message do |result|
            "expected result status to be #{status.inspect}, but got #{result[:status].inspect}"
          end
          failure_message_when_negated do
            "expected result not to have status #{status.inspect}"
          end
        end
      end

      # Asserts against +result[:json]+ using +a_hash_including+ (nested matchers allowed).
      ::RSpec::Matchers.define :have_action_json do |expected_fragment|
        include ::RSpec::Matchers

        match do |result|
          @inner_matcher ||= a_hash_including(expected_fragment)
          next false unless result.is_a?(Hash) && result.key?(:json)

          @inner_matcher.matches?(result[:json])
        end

        failure_message do |result|
          if !result.is_a?(Hash)
            "expected an ActionFigure result hash, got #{result.inspect}"
          elsif !result.key?(:json)
            "expected #{result.inspect} to include key :json (ActionFigure render hash)"
          else
            "expected result[:json] to #{@inner_matcher.description}"
          end
        end

        failure_message_when_negated do |result|
          @inner_matcher ||= a_hash_including(expected_fragment)
          "#{result.inspect} was expected not to match #{@inner_matcher.description}"
        end
      end
    end
  end
end
