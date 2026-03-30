# frozen_string_literal: true

module ActionFigure
  module Testing
    # Minitest assertions for ActionFigure response results.
    #
    # Include in your test class to get assert_Ok, assert_Created, etc.:
    #
    #   class Users::CreateTest < Minitest::Test
    #     include ActionFigure::Testing::Minitest
    #   end
    module Minitest
      def assert_Ok(result, msg = nil)
        assert_status(:ok, result, msg)
      end

      def assert_Created(result, msg = nil)
        assert_status(:created, result, msg)
      end

      def assert_Accepted(result, msg = nil)
        assert_status(:accepted, result, msg)
      end

      def assert_NoContent(result, msg = nil)
        assert_status(:no_content, result, msg)
      end

      def assert_UnprocessableContent(result, msg = nil)
        assert_status(:unprocessable_content, result, msg)
      end

      def assert_NotFound(result, msg = nil)
        assert_status(:not_found, result, msg)
      end

      def assert_Forbidden(result, msg = nil)
        assert_status(:forbidden, result, msg)
      end

      def assert_Conflict(result, msg = nil)
        assert_status(:conflict, result, msg)
      end

      def assert_PaymentRequired(result, msg = nil)
        assert_status(:payment_required, result, msg)
      end

      private

      def assert_status(expected, result, msg)
        actual = result[:status]
        message = msg || "Expected result status to be #{expected.inspect}, but got #{actual.inspect}"
        assert actual == expected, message
      end
    end
  end
end
