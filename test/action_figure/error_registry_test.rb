# frozen_string_literal: true

require "test_helper"

class ErrorRegistryTest < Minitest::Test
  def test_defaults_include_the_five_original_statuses
    statuses = ActionFigure.error_statuses
    assert_equal :unprocessable_content, statuses[:UnprocessableContent]
    assert_equal :not_found, statuses[:NotFound]
    assert_equal :forbidden, statuses[:Forbidden]
    assert_equal :conflict, statuses[:Conflict]
    assert_equal :payment_required, statuses[:PaymentRequired]
  end

  def test_defaults_include_the_new_builtin_4xx_statuses
    statuses = ActionFigure.error_statuses
    assert_equal :gone, statuses[:Gone]
    assert_equal :locked, statuses[:Locked]
    assert_equal :unavailable_for_legal_reasons, statuses[:UnavailableForLegalReasons]
  end

  def test_error_statuses_returns_a_copy_not_the_internal_store
    ActionFigure.error_statuses[:Bogus] = :bogus
    refute ActionFigure.error_statuses.key?(:Bogus),
           "mutating the returned hash must not affect the registry"
  end

  def test_register_error_adds_an_entry
    ActionFigure.register_error(:TooManyRequests, :too_many_requests)
    assert_equal :too_many_requests, ActionFigure.error_statuses[:TooManyRequests]
  end

  def test_register_error_coerces_strings_to_symbols
    ActionFigure.register_error("MisdirectedRequest", "misdirected_request")
    assert_equal :misdirected_request, ActionFigure.error_statuses[:MisdirectedRequest]
  end

  def test_register_error_returns_the_name_symbol
    assert_equal :UpgradeRequired, ActionFigure.register_error(:UpgradeRequired, :upgrade_required)
  end

  def test_register_error_raises_when_overriding_existing_with_different_status
    err = assert_raises(ArgumentError) do
      ActionFigure.register_error(:NotFound, :too_many_requests)
    end
    assert_match "already registered", err.message
    assert_equal :not_found, ActionFigure.error_statuses[:NotFound]
  end

  def test_register_error_idempotent_same_value_does_not_raise
    result = ActionFigure.register_error(:NotFound, :not_found)
    assert_equal :NotFound, result
    assert_equal :not_found, ActionFigure.error_statuses[:NotFound]
  end

  def test_register_error_rejects_unknown_http_status_symbols_at_registration
    err = assert_raises(ArgumentError) do
      ActionFigure.register_error(:BogusStatus, :not_a_real_status)
    end
    assert_match "not_a_real_status", err.message
    refute ActionFigure.error_statuses.key?(:BogusStatus),
           "a rejected status must not land in the registry"
  end

  def test_status_code_for_resolves_rack_status_symbols
    assert_equal 404, ActionFigure.status_code_for(:not_found)
    assert_equal 422, ActionFigure.status_code_for(:unprocessable_content)
  end

  def test_status_code_for_raises_for_unknown_symbols
    err = assert_raises(ArgumentError) { ActionFigure.status_code_for(:nope) }
    assert_match "nope", err.message
  end

  def test_register_error_rejects_names_reserved_by_the_formatter_contract
    %i[Ok Created Accepted NoContent error_response].each do |reserved|
      err = assert_raises(ArgumentError, "#{reserved} must be rejected") do
        ActionFigure.register_error(reserved, :bad_gateway)
      end
      assert_match "reserved", err.message
      refute ActionFigure.error_statuses.key?(reserved),
             "#{reserved} must not land in the registry"
    end
  end
end
