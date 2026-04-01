# Changelog

All notable changes to ActionFigure will be documented in this file.

## [0.6.0] - 2026-03-30

### Added

- `Conflict` (409) and `PaymentRequired` (402) response helpers across all formatters
- Automatic entry point discovery via `method_added` — single public method is detected without needing `entry_point`
- `IndeterminantEntryPointError` raised when multiple public methods exist without an explicit `entry_point`
- Status codes documentation (`docs/status-codes.md`)

### Changed

- `params_schema` is now optional — actions without a schema pass `params:` through unvalidated

## [0.5.0] - 2026-03-25

### Added

- Thread-safe format registry using `Concurrent::Map`
- RBS type signatures for the full public API (`sig/action_figure.rbs`)
- Integration test suite (`test/integration/full_pipeline_test.rb`)

### Fixed

- Schema guard: redefining `params_schema` after `rules` now raises instead of silently dropping rules
- Keyword argument safety: non-params kwargs pass through untouched
- Consistent envelope: `Accepted` without a resource uses `nil` data (not omitted key) in Default and Wrapped formatters
- RSpec negated matcher failure message now shows actual status

## [0.4.0] - 2026-03-21

### Added

- Wrapped formatter (`ActionFigure::Formatters::Wrapped`) with uniform `{ data:, errors:, status: }` envelope
- Default formatter (`ActionFigure::Formatters::Default`) with `{ data: }` envelope
- `ActiveSupport::Notifications` instrumentation (opt-in via `activesupport_notifications` config)
- Cross-parameter rule helpers: `exclusive_rule`, `any_rule`, `one_rule`, `all_rule`
- `meta:` keyword on success response helpers (`Ok`, `Created`, `Accepted`)
- `.contract` accessor for standalone schema/rules introspection
- `api_version` class-level macro for per-action version tagging
- `whiny_extra_params` configuration option
- Minitest assertions (`assert_Ok`, `assert_Created`, etc.) and RSpec matchers (`be_Ok`, `be_Created`, etc.)
- JSON:API formatter with `Resource` serializer for ActiveRecord objects
- Custom formatter registration with load-time validation
- User-facing documentation for all features

### Changed

- `UnprocessableEntity` renamed to `UnprocessableContent` to match Rails 7.1+ naming

## [0.1.0] - 2026-03-20

### Added

- Initial release
- Core validation pipeline powered by dry-validation
- JSend response formatter
- `params_schema` and `rules` DSL
- `ActionController::Parameters` support via `to_unsafe_h`
- `NoContent` response helper
