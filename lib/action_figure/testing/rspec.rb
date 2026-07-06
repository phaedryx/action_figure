# frozen_string_literal: true

require "rspec/matchers"
require_relative "statuses"

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
      def self.define_status_matcher(name, status)
        ::RSpec::Matchers.define :"be_#{name}" do
          match { |result| result.is_a?(Hash) && result[:status] == status }
          failure_message do |result|
            next "expected an ActionFigure result hash, got #{result.inspect}" unless result.is_a?(Hash)

            "expected result status to be #{status.inspect}, but got #{result[:status].inspect}"
          end
          failure_message_when_negated do
            "expected result not to have status #{status.inspect}"
          end
        end
      end

      Testing.statuses.each { |name, status| define_status_matcher(name, status) }

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

      # Asserts an action class's schema/rules accept the given params. Subject is
      # the action class, not a result hash. params_schema actions take the params
      # hash; request_schema actions take locations:
      #
      #   expect(Users::Create).to accept_params(email: "jane@example.com")
      #   expect(Projects::Update).to accept_params(query: { id: 1 }, body: { name: "x" })
      ::RSpec::Matchers.define :accept_params do |params|
        match { |action_class| ActionFigure::Testing.check(action_class, params).success? }

        failure_message do |action_class|
          errors = ActionFigure::Testing.check(action_class, params).errors
          "expected #{action_class} to accept params, but got errors: #{errors.inspect}"
        end

        failure_message_when_negated do |action_class|
          "expected #{action_class} not to accept params #{params.inspect}, but it did"
        end
      end

      # Asserts an action class's params_schema/rules reject the given params.
      # Chain +with_error_on+ to require the failure to land on a specific field:
      #
      #   expect(Users::Create).to reject_params(name: "Jane").with_error_on(:email)
      ::RSpec::Matchers.define :reject_params do |params|
        chain(:with_error_on) { |field| @field = field }

        match do |action_class|
          errors = ActionFigure::Testing.check(action_class, params).errors
          next false if errors.empty?

          @field.nil? || errors.key?(@field)
        end

        failure_message do |action_class|
          errors = ActionFigure::Testing.check(action_class, params).errors
          if @field
            "expected #{action_class} to reject params with an error on #{@field.inspect}, " \
              "but errors were: #{errors.inspect}"
          else
            "expected #{action_class} to reject params #{params.inspect}, but it accepted them"
          end
        end

        failure_message_when_negated do |action_class|
          "expected #{action_class} not to reject params #{params.inspect}"
        end
      end
    end
  end
end
