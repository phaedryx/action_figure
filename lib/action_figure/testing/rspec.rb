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
        Forbidden: :forbidden
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
    end
  end
end
