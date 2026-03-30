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

All assertions accept an optional second argument for a custom failure message:

```ruby
assert_Ok(result, "expected the user to be created successfully")
```

When a status assertion fails, the default message shows the expected and actual status:

```
Expected result status to be :ok, but got :unprocessable_content
```

---

## RSpec

### Setup

Require the helper in your spec support file. No `include` is needed -- the matchers are registered globally:

```ruby
# spec/spec_helper.rb
require "action_figure/testing/rspec"
```

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
    result = Users::CreateAction.call(params: { email: "jane@example.com", name: "Jane" })

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
    result = Users::CreateAction.call(params: { name: "Jane" })

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
    result = Posts::CreateAction.call(params: { title: "Hello", body: "World" }, current_user: user)

    assert_Created(result)
    assert_equal user.id, result[:json][:data][:author_id]
  end
end
```

### Testing a Custom Entry Point

When an action defines a custom class method (e.g., `.search`) instead of the default `.call`, call it by that name:

```ruby
class Products::SearchActionTest < Minitest::Test
  include ActionFigure::Testing::Minitest

  # class SearchAction
  #   include ActionFigure[:jsend]
  #
  #   entry_point :search
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
  #   def call(session:)
  #     session.destroy!
  #     NoContent()
  #   end
  # end
  def test_destroys_the_session
    session = sessions(:active)
    result = Sessions::DestroyAction.call(session: session)

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

This runs both the schema and any `rules` defined on the action -- the same validation pipeline that `.call` uses, without the side effects.

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

---

## Conventions

- **Assert fully** -- for validation and rule failures, assert both the HTTP status and the error message. Testing only the status does not prove the correct validation failed.
- **Named locals, not subject** -- use a descriptive local variable (`result`, `action`) in each test instead of a shared `subject` helper method.
- **Use return values for assertions** -- assert on what `Ok(resource: ...)` returns rather than capturing outer variables with closures.
