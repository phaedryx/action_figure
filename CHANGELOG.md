# Changelog

All notable changes to ActionFigure will be documented in this file.

## [Unreleased]

### Added

- **`request_schema`** class macro — a location-aware alternative to `params_schema`. Declares the HTTP request in OpenAPI's vocabulary via **`path`**/**`query`**/**`body`** locations. The block form declares; the no-args form returns the compiled **`ActionFigure::RequestSchema`** (per-location coercing contracts via `.contracts`, typed value construction), mirroring the `api_version` block/reader duality. `params_schema` is unchanged and not deprecated; an action class declares one or the other, never both.
- Class-load guards for `request_schema`, failing at boot with pointed messages:
  - declaring both `params_schema` and `request_schema` (either order) raises `ArgumentError`
  - duplicate `request_schema` raises `ArgumentError` (parity with the `params_schema` guard)
  - `optional(...)` inside a `path` location raises — OpenAPI path parameters are always required
  - schema keys named **`given?`**, **`given_keys`**, **`to_h`**, or **`deconstruct_keys`** (at any nesting depth, array members included) raise — these names are reserved by the typed request values
  - bare `required`/`optional` declarations outside a location raise with guidance instead of `NoMethodError`
  - a duplicate location block (`body { ... }` twice) raises instead of silently overwriting the first
  - a location called without a block (`path` bare) raises instead of compiling to an empty schema
  - `rules(:location)` declared above the `request_schema` block raises pointing at the declaration order
- dry-schema's **`:info`** extension is now loaded (powers the class-load guards).
- **`request:` invocation pipeline.** `request_schema` actions are called with `request:` (the Rails `ActionDispatch::Request` — duck-typed on `path_parameters`/`query_parameters`/`request_parameters`, so core stays framework-free) instead of `params:`. Each location validates against its actual source: a query-location key arriving in the body is not seen, and same-named keys in different locations are distinct parameters. Controllers: `render Action.update(request:, current_user:)`.
- **Typed request values.** The action method receives `request:` as a frozen, schema-shaped value (`Data`-based, generated once at class load): `request.path.id`, `request.query.workspace_id`, `request.body.name` — coerced and validated; typo'd key access raises `NoMethodError` at the call site. Actions declare only the locations they have.
- **Absent vs. explicit nil is preserved** (PATCH semantics): reads return `nil` for both, **`given?(:key)`** tells them apart, pattern matching (`in { description: }`) matches only keys the client actually sent, and **`to_h`** returns given keys only — matching dry-schema's key-omission behavior.
- **Nested typed values.** Nested hash schemas become nested frozen values (`request.body.project.settings.visibility`) and arrays of hashes become arrays of typed values — with `given?`/`given_keys` at every level. Typed exactly as deep as the contract is explicit: a blockless `hash` (free-form JSON) stays a plain hash. **`to_h`** returns given keys as plain hashes all the way down (safe for `Model.update(request.body.to_h)`); pattern matching binds typed values.
- **`ActionFigure.request(path:, query:, body:)`** — request stand-in for invoking `request_schema` actions from tests and consoles.
- **Path-location failures render `NotFound`** (a malformed identity param means the resource cannot exist; identity wins on mixed failures); other validation failures render `UnprocessableContent` with the familiar flat `{field => [messages]}` errors, merged across locations — same-named keys failing in multiple locations concatenate their messages.
- **`whiny_extra_params` applies to `request_schema` actions** per location: undeclared keys in `query`/`body` return `422` with `"is not allowed"` errors. The `path` location is exempt (router-defined keys plus `:controller`/`:action`/`:format` bookkeeping). Undeclared locations are never read off the request — a `path`/`query`-only schema never triggers body parsing.
- Passing `params:` (or any non-request object) to a `request_schema` action raises `ArgumentError` pointing to `request:` / `ActionFigure.request` — no silent fallback to merged validation.
- **Location-aware contract assertions.** For `request_schema` actions, the contract helpers take locations: Minitest **`assert_valid_params(Action, query: {...}, body: {...})`** / **`assert_invalid_params(..., on: :field)`**; RSpec **`accept_params(query: {...}, body: {...})`** / **`reject_params(...).with_error_on(:field)`**. Omitted locations validate as empty (matching runtime); unknown location names raise listing the declared locations; errors report flat across locations. Omitting params entirely, or mixing a positional params hash with location keywords (including typo'd keywords like `om:`), raises `ArgumentError`. The existing hash forms for `params_schema` actions are unchanged.
- **Location-scoped `rules` for `request_schema`**: `rules(:body) { ... }`, `rules(:query) { ... }`, `rules(:path) { ... }` — one block per declared location, attaching to that location's contract with today's semantics (cross-param helpers included). Path-location rules failures render 404 like path schema failures; others 422. Guards at class load: bare `rules` on a `request_schema` action, rules for an undeclared location, duplicate `rules(location)`, and `rules(:location)` on a `params_schema` action all raise with pointed messages. Cross-location rules live in the method body.

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

### Removed

- The deprecated `IndeterminantEntryPointError` alias (misspelled constant shipped through 0.6.0, aliased in 0.6.1). Use **`IndeterminateEntryPointError`**; update any remaining `rescue` clauses.

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
