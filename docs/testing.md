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

class Users::CreateTest < Minitest::Test
  include ActionFigure::Testing::Minitest
end
```

### Assertions

| Assertion                      | Expected status         |
|-------------------------------|-------------------------|
| `assert_Ok(result)`           | `:ok`                   |
| `assert_Created(result)`      | `:created`              |
| `assert_Accepted(result)`     | `:accepted`             |
| `assert_NoContent(result)`    | `:no_content`           |
| `assert_UnprocessableEntity(result)` | `:unprocessable_content` |
| `assert_NotFound(result)`     | `:not_found`            |
| `assert_Forbidden(result)`    | `:forbidden`            |

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

| Matcher              | Expected status         |
|---------------------|-------------------------|
| `be_Ok`             | `:ok`                   |
| `be_Created`        | `:created`              |
| `be_Accepted`       | `:accepted`             |
| `be_NoContent`      | `:no_content`           |
| `be_UnprocessableEntity` | `:unprocessable_content` |
| `be_NotFound`       | `:not_found`            |
| `be_Forbidden`      | `:forbidden`            |

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

### Testing a Successful Action

Define an anonymous action class inline, call it, and assert both the status and the returned data:

```ruby
class Users::CreateTest < Minitest::Test
  include ActionFigure::Testing::Minitest

  def test_creates_a_user
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:email).filled(:string)
        required(:name).filled(:string)
      end

      def call(params:, **)
        user = User.create!(params)
        Ok(resource: user)
      end
    end

    result = action.call(params: { email: "jane@example.com", name: "Jane" })

    assert_Ok(result)
    assert_equal "jane@example.com", result[:json][:data].email
    assert_equal "Jane", result[:json][:data].name
  end
end
```

### Testing Validation Failure

When testing validation failures, assert both the status and the error message content. Testing only the status is insufficient -- it does not prove the right validation failed.

```ruby
class Users::CreateTest < Minitest::Test
  include ActionFigure::Testing::Minitest

  def test_rejects_missing_email
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:email).filled(:string)
        required(:name).filled(:string)
      end

      def call(params:, **)
        user = User.create!(params)
        Ok(resource: user)
      end
    end

    result = action.call(params: { name: "Jane" })

    assert_UnprocessableEntity(result)
    assert_includes result[:json][:data][:email], "is missing"
  end
end
```

### Testing with Dependency Injection

Actions often receive context such as `current_user:` as keyword arguments alongside `params:`. Pass them directly in the test:

```ruby
class Posts::CreateTest < Minitest::Test
  include ActionFigure::Testing::Minitest

  def test_creates_a_post_for_the_current_user
    action = Class.new do
      include ActionFigure[:jsend]

      params_schema do
        required(:title).filled(:string)
        required(:body).filled(:string)
      end

      def call(params:, current_user:, **)
        post = current_user.posts.create!(params)
        Created(resource: post)
      end
    end

    user = users(:jane)
    result = action.call(params: { title: "Hello", body: "World" }, current_user: user)

    assert_Created(result)
    assert_equal user, result[:json][:data].author
  end
end
```

### Testing a Custom Entry Point

When an action defines a custom class method (e.g., `.search`) instead of the default `.call`, call it by that name:

```ruby
class Products::SearchTest < Minitest::Test
  include ActionFigure::Testing::Minitest

  def test_finds_matching_products
    action = Class.new do
      include ActionFigure[:jsend]

      entry_point :search

      params_schema do
        required(:query).filled(:string)
      end

      def search(params:, **)
        products = Product.where("name ILIKE ?", "%#{params[:query]}%")
        Ok(resource: products)
      end
    end

    result = action.search(params: { query: "keyboard" })

    assert_Ok(result)
    assert result[:json][:data].any?, "expected at least one matching product"
  end
end
```

### Testing NoContent

Actions that perform side effects without returning data use `NoContent()`:

```ruby
class Sessions::DestroyTest < Minitest::Test
  include ActionFigure::Testing::Minitest

  def test_destroys_the_session
    action = Class.new do
      include ActionFigure[:jsend]

      def call(session:, **)
        session.destroy!
        NoContent()
      end
    end

    session = sessions(:active)
    result = action.call(session: session)

    assert_NoContent(result)
  end
end
```

---

## Conventions

- **Assert fully** -- for validation and rule failures, assert both the HTTP status and the error message. Testing only the status does not prove the correct validation failed.
- **Named locals, not subject** -- use a descriptive local variable (`result`, `action`) in each test instead of a shared `subject` helper method.
- **Use `def`, not `define_method`** -- define action methods with regular `def call(params:)` syntax inside anonymous test classes.
- **Use return values for assertions** -- assert on what `Ok(resource: ...)` returns rather than capturing outer variables with closures.
