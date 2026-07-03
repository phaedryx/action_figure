# Changelog

All notable changes to ActionFigure will be documented in this file.

## [0.7.0] - 2026-07-02

### Added

- **Central error-status registry.** `ActionFigure.error_statuses` lists every error helper (name → Rack status symbol); `ActionFigure.register_error(:BadGateway, :bad_gateway)` adds new ones. Generated helpers live on a registry module included into `ActionFigure::Formatter`, so a registered status is immediately available in **every** formatter, in action classes that were composed **before** the registration, and as `assert_*`/`refute_*`/`be_*` test helpers.
- New built-in error statuses: **`Gone`** (410), **`Locked`** (423), and **`UnavailableForLegalReasons`** (451).
- `ActionFigure.status_code_for(status_symbol)` — resolves a Rack status symbol to its numeric code (accepts both `:unprocessable_content` and `:unprocessable_entity` on every supported Rack version).
- `register_error` validates its status symbol against Rack's status table and rejects helper names reserved by the formatter contract, so typos fail at boot instead of on the first rendered error.
- `:rfc_9457` formatter implementing RFC 9457 Problem Details for HTTP APIs.
  Errors render as `application/problem+json` with `type`, `title`, `status`,
  `detail`, `instance`, and extension members. Success responses use the same
  vocabulary (`type`, `title`, named resource key). Defaults derive from class
  names and status symbols; all members accept override kwargs.
- Generated error helpers now accept `errors: nil` (previously required) and
  forward `**extras` to `error_response`. Existing formatters are unaffected
  when called without extras.
- **Contract assertions** — test an action's **`params_schema`**/**`rules`** in isolation, without invoking the action body. Minitest: **`assert_valid_params(action_class, params)`** and **`assert_invalid_params(action_class, params, on: :field)`**. RSpec: **`accept_params(params)`** and **`reject_params(params).with_error_on(:field)`** (subject is the action class). These are formatter-agnostic. Both raise a clear **`ArgumentError`** for actions without a **`params_schema`**.
- **`assert_action_json`** / **`refute_action_json`** Minitest assertions — partial match on **`result[:json]`**, mirroring the RSpec **`have_action_json`** matcher. Nested Hashes match as subsets and **`Regexp`** values match against strings.
- Negated Minitest status assertions: **`refute_Ok`**, **`refute_Created`**, … for every status (parity with RSpec **`not_to be_Ok`**).

### Changed

- **Formatter contract shrank from 8 methods to 4**: `Ok`, `Created`, `Accepted`, and the new `error_response(errors:, status:)`. Named error helpers (`NotFound`, `Conflict`, …) are generated from the registry and delegate to `error_response`; a hand-defined named helper on a formatter still wins.
- The gem now declares a runtime dependency on **rack** (>= 2.2), used to resolve and validate status codes.
- Status helpers for both adapters are now generated from the live registry (**`ActionFigure::Testing.statuses`**, including **`NoContent`**), so the Minitest and RSpec lists can no longer drift and newly registered statuses appear automatically. Replaces the RSpec-only **`ActionFigure::Testing::RSpec::MATCHERS`** constant.
- Status assertions/matchers now fail with a clear "expected an ActionFigure result hash" message when given a non-Hash, instead of raising **`NoMethodError`**.

### Known limitation

- There is **no** formatter-agnostic assertion for **non-validation** error bodies (e.g. **`NotFound`**/**`Conflict`** with a custom **`errors:`** payload). Each formatter stores errors differently (**`json[:errors]`** vs **`json[:data]`** vs a JSON:API array) and the result hash carries no formatter identity. Assert those with a format-specific **`assert_action_json`** / **`have_action_json`**. Validation errors are best tested via the contract assertions above.

## [0.6.2] - 2026-06-25

### Fixed

- Without a **`params_schema`**, params now pass through **untouched** — **`to_unsafe_h`** is only called when there is a schema to validate against. Previously an **`ActionController::Parameters`** (or any object responding to **`to_unsafe_h`**) was unwrapped into a plain hash even with no schema, contradicting the 0.6.0 "no schema → params pass through unvalidated" contract. **Breaking** for code that relied on the implicit unwrap; such actions should unwrap (e.g. via strong params) themselves.

### Documentation

- **`README.md`**: simplify the before/after hint that prompts readers to spot the incorrect render response.

## [0.6.1] - 2026-05-23

### Added

- **`have_action_json`** RSpec matcher (partial match on **`result[:json]`** via **`a_hash_including`**).
- Notifications payload **`entry_point`** (Symbol) alongside **`action`** for **`process.action_figure`**.
- **`InitializationNotSupportedError`** when an action class defines **`initialize`** (instances are built with arity-zero **`new`**).
- CI job running **`bundle exec rbs validate`**.
- Regression test asserting built-in formatters expose **`Formatter::REQUIRED_METHODS`** (+ **`NoContent`**).

### Changed

- Renamed `IndeterminantEntryPointError` → **`IndeterminateEntryPointError`** (raised when multiple public entry methods exist without `entry_point`). The old constant remains as a deprecated alias (`Module#deprecate_constant`) for one release; update any `rescue` clauses to the new spelling.
- **`params_schema`** may only be called once per action class; a duplicate call raises **`ArgumentError`** (previously enforced only when a **`rules`** block was already present).

### Documentation

- Load-order semantics for **`ActionFigure.configure`** (default **`format`** and **`activesupport_notifications`** latch when each class **`include`** runs).
- Testing guide: matchers/assertions inspect **`[:status]`** only; RSpec **`require`** order.
- Actions guide: mermaid overview of **`method_added`** / **`entry_point`** discovery.
- Actions guide: do not define **`initialize`** on actions (arity-zero **`new`**); use **`InitializationNotSupportedError`** when violated.
- Actions guide: **`api_version`** — clarify global (**`configure`**) vs class macro (**no fallback**).
- **`README.md`**: `:unprocessable_entity` vs ActionFigure **`result[:status]`** symbol **`:unprocessable_content`**.
- Configuration guide: **thread safety** / singleton **`ActionFigure.configuration`** semantics.
- ActiveSupport Notifications: payload documents **`entry_point`**; subscriber examples reference it.
- Testing guide: **`have_action_json`** RSpec matcher.

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
