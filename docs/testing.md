# Testing

## Overview

ActionFigure actions return plain hashes, making them straightforward to test without controller setup or request scaffolding. You call the action directly, receive a result, and assert against it.

Both Minitest and RSpec helpers are provided. They wrap status checks in expressive, intention-revealing assertions so your tests read clearly.

---

## Minitest

### Setup

Require the helper and include the module in your test class:

```ruby
require "action_figure/testing/minitest"

class Users::CreateActionTest < Minitest::Test
  include ActionFigure::Testing::Minitest
end
```

### Assertions

| Assertion                             | Expected status          |
|---------------------------------------|--------------------------|
| `assert_Ok(result)`                   | `:ok`                    |
| `assert_Created(result)`              | `:created`               |
| `assert_Accepted(result)`             | `:accepted`              |
| `assert_NoContent(result)`            | `:no_content`            |
| `assert_UnprocessableContent(result)` | `:unprocessable_content` |
| `assert_NotFound(result)`             | `:not_found`             |
| `assert_Forbidden(result)`            | `:forbidden`             |
| `assert_Conflict(result)`             | `:conflict`              |
| `assert_PaymentRequired(result)`      | `:payment_required`      |
| `assert_Gone(result)`                 | `:gone`                  |
| `assert_Locked(result)`               | `:locked`                |
| `assert_UnavailableForLegalReasons(result)` | `:unavailable_for_legal_reasons` |

Each status assertion has a negated counterpart — **`refute_Ok`**, **`refute_Created`**, … — that passes when the status is anything *other* than the named one. Statuses added with `ActionFigure.register_error` get matching `assert_*`/`refute_*` helpers automatically, whether registered before or after this adapter loads.

These helpers compare **only `result[:status]`** against the Rack-style symbol Rails uses in **`render`** — they **do not** assert on **`[:json]`** keys, payloads, or error message text. Combine them with assertions on **`result[:json]`** (or matchers on the body your formatter produces) whenever shape matters.

All assertions accept an optional second argument for a custom failure message:

```ruby
assert_Ok(result, "expected the user to be created successfully")
```

When a status assertion fails, the default message shows the expected and actual status:

```
Expected result status to be :ok, but got :unprocessable_content
```

### Asserting on the body

Use **`assert_action_json`** to match a (possibly nested) subset of **`result[:json]`** — the Minitest counterpart to RSpec's **`have_action_json`**. Nested Hashes match as subsets, and **`Regexp`** values match against strings:

```ruby
assert_action_json(result, status: "success")
assert_action_json(result, status: "success", data: { name: "Jane" })
assert_action_json(result, data: { email: /@example\.com\z/ })
```

**`refute_action_json`** passes when the fragment does **not** match. Both fail with a clear message when given a non-result value or a hash missing the **`:json`** key.

---

## RSpec

### Setup

Require the helper in your spec support file. No `include` is needed -- the matchers are registered globally:

```ruby
# spec/spec_helper.rb
require "action_figure/testing/rspec"
```

**Load order:** require this library **after** RSpec Core and expectations load (usual practice: append it toward the **bottom** of `spec/spec_helper.rb`, after any `require "rails_helper"` / `RSpec.configure` boilerplate from your app). ActionFigure pulls in **`rspec/matchers`**; minimalist scripts without the full **`rspec` CLI shim** must **`require "rspec/expectations"`** (and typically **`require "rspec/core"`**) *before* this file.

### Matchers

| Matcher                   | Expected status          |
|---------------------------|--------------------------|
| `be_Ok`                   | `:ok`                    |
| `be_Created`              | `:created`               |
| `be_Accepted`             | `:accepted`              |
| `be_NoContent`            | `:no_content`            |
| `be_UnprocessableContent` | `:unprocessable_content` |
| `be_NotFound`             | `:not_found`             |
| `be_Forbidden`            | `:forbidden`             |
| `be_Conflict`             | `:conflict`              |
| `be_PaymentRequired`      | `:payment_required`      |
| `be_Gone`                 | `:gone`                  |
| `be_Locked`               | `:locked`                |
| `be_UnavailableForLegalReasons` | `:unavailable_for_legal_reasons` |
| `have_action_json`        | `result[:json]` matches `a_hash_including(fragment)` |
| `accept_params(params)`   | action class's contract accepts `params` |
| `reject_params(params)`   | action class's contract rejects `params` (chain `.with_error_on(:field)`) |

Like the Minitest helpers, each **`be_*`** matcher compares **only `result[:status]`** — **`[:json]`** is ignored unless you assert on it separately. Use **`have_action_json`** when you want a focused assertion against the **`json`** body (compose with **`a_hash_including`** for nested subsets):

```ruby
expect(result).to be_Ok
expect(result).to have_action_json(status: "success")
expect(result).to have_action_json(
  status: "success",
  data: a_hash_including(name: "Jane")
)
```

Matchers support negation:

```ruby
expect(result).to be_Ok
expect(result).not_to be_Forbidden
```

Failure messages mirror the Minitest style:

```
expected result status to be :ok, but got :unprocessable_content
```

---

## Testing Patterns

The examples below use Minitest, but the same patterns apply to RSpec with the corresponding matchers.

The examples below use the JSend formatter (`ActionFigure[:jsend]`) for consistency. The structure of `result[:json]` depends on your chosen formatter — see [Response Formatters](response-formatters.md) for the shape each format produces.

### Testing a Successful Action

Call your class and assert both the status and the returned data:

```ruby
class Users::CreateActionTest < Minitest::Test
  include ActionFigure::Testing::Minitest

  def test_creates_a_user
    result = Users::CreateAction.create(params: { email: "jane@example.com", name: "Jane" })

    assert_Ok(result)
    assert_equal "jane@example.com", result[:json][:data][:email]
    assert_equal "Jane", result[:json][:data][:name]
  end
end
```

### Testing Validation Failure

When testing validation failures, assert both the status and the error message content. Testing only the status is insufficient -- it does not prove the correct validation failed.

```ruby
class Users::CreateActionTest < Minitest::Test
  include ActionFigure::Testing::Minitest

  def test_rejects_missing_email
    result = Users::CreateAction.create(params: { name: "Jane" })

    assert_UnprocessableContent(result)
    assert_includes result[:json][:data][:email], "is missing"
  end
end
```

### Testing with Context Injection

Actions often receive context such as `current_user:` as keyword arguments alongside `params:`. Pass them directly in the test:

```ruby
class Posts::CreateActionTest < Minitest::Test
  include ActionFigure::Testing::Minitest

  def test_creates_a_post_for_the_current_user
    user = users(:jane)
    result = Posts::CreateAction.create(params: { title: "Hello", body: "World" }, current_user: user)

    assert_Created(result)
    assert_equal user.id, result[:json][:data][:author_id]
  end
end
```

### Testing an Action with a Named Method

Call the action using its discovered method name:

```ruby
class Products::SearchActionTest < Minitest::Test
  include ActionFigure::Testing::Minitest

  # class SearchAction
  #   include ActionFigure[:jsend]
  #
  #   params_schema do
  #     required(:query).filled(:string)
  #   end
  #
  #   def search(params:, **)
  #     products = Product.where("name ILIKE ?", "%#{params[:query]}%")
  #     Ok(resource: products)
  #   end
  # end
  def test_finds_matching_products
    result = SearchAction.search(params: { query: "keyboard" })

    assert_Ok(result)
    assert result[:json][:data].any?, "expected at least one matching product"
  end
end
```

### Testing NoContent

Actions that perform side effects without returning data use `NoContent()`:

```ruby
class Sessions::DestroyActionTest < Minitest::Test
  include ActionFigure::Testing::Minitest

  # class Sessions::DestroyAction
  #   include ActionFigure[:jsend]
  #
  #   def destroy(session:)
  #     session.destroy!
  #     NoContent()
  #   end
  # end
  def test_destroys_the_session
    session = sessions(:active)
    result = Sessions::DestroyAction.destroy(session: session)

    assert_NoContent(result)
  end
end
```

---

## Standalone Validation with `.contract`

Every action that defines a `params_schema` exposes the underlying validation contract via `.contract`. This returns a `Dry::Validation::Contract` instance that you can call directly -- useful for validating input without executing the action.

```ruby
contract = Users::CreateAction.contract
result = contract.call(email: "jane@example.com", name: "Jane")

result.success?    # => true
result.to_h        # => { email: "jane@example.com", name: "Jane" }
```

When validation fails, inspect the errors:

```ruby
result = Users::CreateAction.contract.call(email: "", name: "Jane")

result.failure?      # => true
result.errors.to_h   # => { email: ["must be filled"] }
```

This runs both the schema and any `rules` defined on the action -- the same validation pipeline that the class-level trigger uses, without the side effects.

Actions that do not define a `params_schema` return `nil` from `.contract`.

### Inspecting schema and rules

The contract exposes the schema and rules for introspection:

```ruby
contract = Users::CreateAction.contract

contract.schema                        # => the Dry::Schema::Params instance
contract.schema.key_map.map(&:name)    # => ["email", "name"]

contract.rules                         # => array of Dry::Validation::Rule objects
contract.rules.map(&:keys)            # => [[:email]]
```

This is useful for building documentation generators, admin panels, or debugging which validations an action enforces.

### When to use `.contract` directly

- **Form validation endpoints** -- validate input and return errors without creating or modifying resources.
- **Testing validation rules in isolation** -- assert that specific inputs produce specific errors without needing to stub dependencies that `#call` would use.
- **REPL exploration** -- inspect what an action expects by calling its contract interactively.

```ruby
class Users::CreateActionTest < Minitest::Test
  def test_email_is_required
    result = Users::CreateAction.contract.call(name: "Jane")

    assert result.failure?
    assert_includes result.errors.to_h[:email], "is missing"
  end
end
```

### Contract assertion helpers

The testing adapters wrap the `.contract.call` boilerplate above in intention-revealing helpers. They are **formatter-agnostic** — they exercise the validation pipeline directly, so the same assertions work regardless of which formatter the action includes.

**Minitest** — the subject is the action class:

```ruby
class Users::CreateActionTest < Minitest::Test
  include ActionFigure::Testing::Minitest

  def test_accepts_valid_params
    assert_valid_params(Users::CreateAction, { email: "jane@example.com", name: "Jane" })
  end

  def test_requires_email
    # passes when the contract rejects the params at all
    assert_invalid_params(Users::CreateAction, { name: "Jane" })

    # scope to a field: passes only when :email is among the errors
    assert_invalid_params(Users::CreateAction, { name: "Jane" }, on: :email)
  end
end
```

**RSpec** — the subject is the action class, not a result hash:

```ruby
RSpec.describe Users::CreateAction do
  it "accepts valid params" do
    expect(Users::CreateAction).to accept_params(email: "jane@example.com", name: "Jane")
  end

  it "requires email" do
    expect(Users::CreateAction).to reject_params(name: "Jane")
    expect(Users::CreateAction).to reject_params(name: "Jane").with_error_on(:email)
  end
end
```

Both adapters raise a clear **`ArgumentError`** when the action class declares no **`params_schema`** (and therefore has no contract to validate against).

> **Validation errors vs. error bodies.** These helpers are the right tool for asserting *validation* behavior. There is no formatter-agnostic helper for **non-validation** error bodies (e.g. a `NotFound`/`Conflict` you return with a custom `errors:` payload) — each formatter stores those differently and the result hash carries no formatter identity. Assert those with a format-specific `assert_action_json` / `have_action_json`.

---

## Conventions

- **Assert fully** -- for validation and rule failures, assert both the HTTP status and the error message. Testing only the status does not prove the correct validation failed.
- **Named locals, not subject** -- use a descriptive local variable (`result`, `action`) in each test instead of a shared `subject` helper method.
- **Use return values for assertions** -- assert on what `Ok(resource: ...)` returns rather than capturing outer variables with closures.
