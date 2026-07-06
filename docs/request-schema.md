# Request Schema

## Overview

`request_schema` is a location-aware alternative to `params_schema`. Where `params_schema` validates the merged params hash Rails hands you, `request_schema` describes the HTTP request in OpenAPI's vocabulary — **where** each parameter arrives (`path`, `query`, or `body`) — and enforces it: a param documented as a query parameter is simply not seen if a client sends it in the body.

```ruby
class Projects::UpdateAction
  include ActionFigure[:jsend]

  request_schema do
    path  { required(:id).filled(:integer) }
    query { required(:workspace_id).filled(:integer) }
    body do
      required(:name).filled(:string)
      optional(:description).maybe(:string)
    end
  end

  def update(request:, current_user:)
    project = current_user.projects.find(request.path.id)
    project.update(name: request.body.name)
    Ok(resource: ProjectBlueprint.render_as_hash(project))
  end
end
```

```ruby
# controller — `request` is already there (Ruby 3.1 shorthand)
def update
  render Projects::UpdateAction.update(request:, current_user:)
end
```

Each location block uses the same [dry-schema](https://dry-rb.org/gems/dry-schema/) DSL as `params_schema`, with the same coercion (`"42"` → `42`).

### Choosing a macro

The two macros form a ladder with schema-less actions at the bottom — each rung adds contract strength as an endpoint's audience grows:

1. **No schema** — params pass through untouched (health checks, actions relying on upstream validation).
2. **`params_schema`** — validates the merged params hash. The lightweight tier for endpoints with no external contract.
3. **`request_schema`** — validates by location, for endpoints whose request shape is a published contract (public APIs, OpenAPI documents).

An action class declares one or the other, never both — a second declaration of either kind raises `ArgumentError` at class load. `params_schema` is not deprecated and its behavior is unchanged.

---

## Calling convention: `request:`

`request_schema` actions take `request:` instead of `params:` — the Rails request object (`ActionDispatch::Request`) in controllers, or a stand-in built with `ActionFigure.request` everywhere else (a plain `Rack::Request` does not qualify — the duck type needs `path_parameters`/`query_parameters`/`request_parameters`, which ActionDispatch adds):

```ruby
# controller
Projects::UpdateAction.update(request:, current_user:)

# test or console
Projects::UpdateAction.update(
  request: ActionFigure.request(
    path:  { id: "7" },
    query: { workspace_id: "42" },
    body:  { name: "Roadmap" }
  ),
  current_user: user
)
```

ActionFigure duck-types on `path_parameters` / `query_parameters` / `request_parameters`, so core stays framework-free. Passing `params:` — or anything that doesn't quack like a request — raises `ArgumentError` pointing you at `request:` / `ActionFigure.request`. There is no silent fallback to merged validation: that would reopen the accepts-params-anywhere hole the macro exists to close.

`request:` is a reserved keyword argument on `request_schema` actions; other keyword arguments (`current_user:`, etc.) pass through untouched, exactly as with `params:` actions.

---

## Validation semantics

**Each location validates against its actual source.** Rails merges query, body, and path params into one hash (precedence: path > body > query), which makes location enforcement impossible after the fact — an action documented as taking `workspace_id` in the query would silently accept it from the body, and clients end up depending on undocumented behavior. `request_schema` never merges:

- A `query`-location key arriving via the body is **not seen** (schema-as-filter, same posture as `params_schema`).
- `query` and `body` may both declare the same key — they are distinct parameters, as they are in OpenAPI, addressed as `request.query.limit` and `request.body.limit`. When the same key fails in more than one location, the error messages concatenate under that key.

**Failure statuses follow the location:**

| Failing location | Status | Why |
|---|---|---|
| `path` | `404 NotFound` | A malformed identity param (`GET /projects/abc` with integer `id`) means the resource cannot exist — matching what `find` would produce. Identity wins on mixed failures. |
| `query`, `body` | `422 UnprocessableContent` | The familiar flat `{field => [messages]}` errors, merged across locations. |

**Boot-time guards** — declaration mistakes fail at class load, not at request time:

- `optional(...)` inside a `path` location raises (OpenAPI path parameters are always required).
- Schema keys named `given?`, `given_keys`, `to_h`, or `deconstruct_keys` raise at any nesting depth — those names are reserved by the typed request values.
- Bare `required`/`optional` outside a location block raises with guidance.
- A duplicate location block (`body { ... }` twice) raises — silently overwriting the first would drop its validations.
- A location called without a block (`path` bare) raises — it would otherwise compile to an empty schema that validates everything.
- `rules(:location)` above the `request_schema` block raises, pointing at the declaration order.

**`whiny_extra_params` applies here too.** With [`whiny_extra_params`](configuration.md) enabled, undeclared keys in `query` or `body` return `422` with `"is not allowed"` errors, same as `params_schema`. The `path` location is exempt: the router, not the client, defines path keys, and `path_parameters` carries bookkeeping entries (`:controller`, `:action`, `:format`).

---

## The typed request value

Your method receives `request:` — not the Rails request, but a frozen, validated value shaped exactly like your schema (the same transform `params:` performs today: framework object in, validated data out). Locations are readers, keys are methods:

```ruby
request.path.id             # => 7 (coerced)
request.query.workspace_id  # => 42
request.body.name           # => "Roadmap"
request.body.naem           # => NoMethodError — typos fail at the call site
```

Nested hash schemas become nested values, and arrays of hashes become arrays of values:

```ruby
body do
  required(:project).hash do
    required(:name).filled(:string)
    required(:tags).array(:hash) do
      required(:label).filled(:string)
    end
  end
end

request.body.project.name              # => "Roadmap"
request.body.project.tags.first.label  # => "api"
```

Values are typed **exactly as deep as the contract is explicit**: a blockless `hash` (free-form JSON — metadata blobs, pass-through payloads) has no declared shape, so it stays a plain hash. Its interior keeps JSON's string keys and sits outside validation — the typing boundary and the contract boundary are the same line.

### Absent vs. explicit nil (`given?`)

For PATCH semantics, "the client didn't send `description`" and "the client sent `description: null`" must stay distinguishable. Reads return `nil` for both; the given-key set tells them apart:

```ruby
request.body.description           # => nil (either case — reads stay simple)
request.body.given?(:description)  # => false if omitted, true if sent (even as null)
request.body.given_keys            # => the frozen set of keys the client sent

# PATCH: only touch fields the client sent
project.update(description: request.body.description) if request.body.given?(:description)
```

Pattern matching matches **only given keys**, and bindings stay typed:

```ruby
case request.body
in { description: }   # matches only when the client sent it (even as null)
  update_description(description)
else                  # absent → leave the field alone
end
```

`to_h` returns given keys only, as plain hashes all the way down — safe to hand straight to a model:

```ruby
project.update(request.body.to_h)
```

---

## Location-scoped rules

`rules` on a `request_schema` action names the location it constrains — one block per declared location, with the same semantics as `params_schema` rules (cross-param helpers included; rules run only on keys that passed the schema):

```ruby
request_schema do
  query do
    required(:from).filled(:date)
    required(:to).filled(:date)
  end
  body do
    optional(:user_id).filled(:integer)
    optional(:email).filled(:string)
  end
end

rules(:query) do
  rule(:from, :to) do
    key(:from).failure("must be before to") if values[:from] > values[:to]
  end
end

rules(:body) do
  exclusive_rule(:user_id, :email, "provide one, not both")
end
```

Failure statuses follow the location, as above: `rules(:path)` failures render 404, others 422.

Guards at class load: bare `rules` on a `request_schema` action raises (name the location); rules for an undeclared location raise, listing the declared ones; a duplicate `rules(:location)` raises; and `rules(:location)` on a `params_schema` action raises (locations are a `request_schema` concept — bare block there, unchanged).

Cross-**location** rules (a query param exclusive with a body field) are rare and usually an API-design smell; when needed, express them in the method body with an explicit `UnprocessableContent(...)` return.

---

## Testing

See the [testing guide](testing.md) for the full assertion reference. The short version — contract assertions take locations:

```ruby
# Minitest
assert_valid_params(Projects::UpdateAction, query: { workspace_id: "1" }, body: { name: "x" })
assert_invalid_params(Projects::UpdateAction, body: { name: "" }, on: :name)

# RSpec
expect(Projects::UpdateAction).to accept_params(query: { workspace_id: "1" }, body: { name: "x" })
expect(Projects::UpdateAction).to reject_params(body: { name: "x" }).with_error_on(:workspace_id)
```

Omitted locations validate as empty — matching runtime, where a missing required query param fails. Unknown location names raise, listing the declared locations.

Full invocations use `ActionFigure.request`, which states where each param arrives — the exact claim your schema makes:

```ruby
result = Projects::UpdateAction.update(
  request: ActionFigure.request(path: { id: "7" }, body: { name: "Roadmap" }),
  current_user: user
)

assert_Ok(result)
```

---

## Introspection

The no-args form returns the compiled schema (mirroring `api_version`):

```ruby
Projects::UpdateAction.request_schema
# => #<ActionFigure::RequestSchema ...>

Projects::UpdateAction.request_schema.contracts
# => { path: #<Dry::Schema...>, query: #<Dry::Schema...>, body: #<Dry::Validation::Contract...> }
```

Locations with rules attached expose a `Dry::Validation::Contract`; schema-only locations expose a `Dry::Schema::Params`.

---

## Limitations

- **JSON bodies only.** Multipart/form-data and file uploads are not supported by `request_schema` — upload endpoints keep `params_schema` or handle the perimeter in the controller. (Signed-URL uploads sidestep this entirely: every endpoint stays JSON.)
- **Headers are a perimeter concern**, not a location. Auth (`Authorization`), content negotiation (`Accept`), and rate limiting belong to base controllers and middleware — see [Status Codes](status-codes.md). When a specific header *is* domain input (an `Idempotency-Key`, an `If-Match` ETag), extract it in the controller and pass it as a keyword argument, exactly like `current_user` or any other context:

  ```ruby
  def create
    render Payments::CreateAction.create(
      request:,
      current_user:,
      idempotency_key: request.headers["Idempotency-Key"]
    )
  end
  ```
- **Naming caveat:** `request.path` and `request.body` reuse OpenAPI's location vocabulary, which shadows well-known Rails request API names of different types (Rails' `request.path` is a URL string; `request.body` is an IO). The typed value is not the Rails request — a `NoMethodError` on the missing Rails API makes the confusion loud.
- Like `params_schema`, `request_schema` state is not inherited by subclasses — define each action class independently.
