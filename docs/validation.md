# Validation

## Overview

ActionFigure provides a two-layer validation pipeline powered by [dry-validation](https://dry-rb.org/gems/dry-validation/). The pipeline runs **before** your `#call` method, so if validation fails, your operation logic is never executed. The caller receives an `UnprocessableContent` result containing structured errors.

The two layers are:

1. **`params_schema`** -- structural validation and type coercion (powered by dry-schema)
2. **`rules`** -- validation rules that run only after the schema passes

If `params:` is not passed to the action at all, validation is skipped entirely and `#call` is invoked directly. If `params:` is passed but no `params_schema` is defined, an `ArgumentError` is raised immediately.

---

## params_schema

`params_schema` accepts a block written in the [dry-schema](https://dry-rb.org/gems/dry-schema/) DSL. It defines the shape of your input: which keys are allowed, which are required, and what types they must be.

```ruby
class Users::CreateAction
  include ActionFigure[:jsend]

  params_schema do
    required(:email).filled(:string)
    required(:name).filled(:string)
    optional(:age).filled(:integer)
    optional(:newsletter).filled(:bool)
  end

  def call(params:, **)
    user = User.create!(params)
    resource = UserBlueprint.render_as_hash(user)
    Ok(resource:)
  end
end
```

### required vs optional

- `required(:field)` -- the key **must** be present in the input. If missing, validation fails before rules ever run.
- `optional(:field)` -- the key may be omitted. If present, it still must satisfy the declared type and predicates.

### Type coercion

Because ActionFigure uses a **params** schema (not a plain schema), dry-schema automatically coerces string values into their declared types. This is essential for web requests where everything arrives as a string.

```ruby
params_schema do
  required(:quantity).filled(:integer)
  required(:price).filled(:float)
  required(:active).filled(:bool)
end

# Input:  { quantity: "25", price: "9.99", active: "true" }
# Output: { quantity: 25,   price: 9.99,   active: true }
```

Common coercible types: `:string`, `:integer`, `:float`, `:decimal`, `:bool`, `:date`, `:time`, `:date_time`.

---

## rules

`rules` run **after** the schema passes, giving you access to fully validated and coerced values. Use `rules` for constraints that span multiple fields or require context that the schema DSL cannot express (e.g., database lookups). ActionFigure includes several cross-parameter helpers (documented below) to simplify common multi-field rules.

```ruby
class Users::CreateAction
  include ActionFigure[:jsend]

  params_schema do
    required(:email).filled(:string)
    required(:name).filled(:string)
  end

  rules do
    rule(:email) do
      if values[:email] && User.exists?(email: values[:email])
        key.failure("is already taken")
      end
    end
  end

  def call(params:, **)
    user = User.create!(params)
    Ok(resource: user)
  end
end
```

### Key details

- `rules` **must** be declared after `params_schema`. Declaring it without a schema raises:

  ```
  ArgumentError: rules requires params_schema to be defined
  ```

- Inside a rule block, access validated values with `values[:field]`.
- Add an error to a specific field with `key(:field).failure("message")`, or `key.failure("message")` when the rule is scoped to a single field via `rule(:field)`.
- Multiple rules can target the same field. All rules run even if earlier ones fail -- errors accumulate.

---

## Cross-Param Rule Helpers

ActionFigure ships five helpers for common multi-field constraints. They are available inside `rules` blocks and save you from writing the same boilerplate patterns repeatedly.

All helpers share a consistent definition of **"present"**: a field is considered present when its key exists in the validated values **and** its value is not `nil`. Notably, `false` counts as present -- only `nil` (or a missing key) counts as absent.

### exclusive_rule

At most one of the listed fields may be present. If multiple are present, each **present** field receives the error message.

```ruby
class Orders::SearchAction
  include ActionFigure[:jsend]
  params_schema do
    optional(:order_id).filled(:string)
    optional(:tracking_number).filled(:string)
    optional(:customer_email).filled(:string)
  end

  rules do
    exclusive_rule(:order_id, :tracking_number, :customer_email,
                   "provide only one search criterion")
  end

  def call(params:, **)
    # exactly zero or one search key is guaranteed here
  end
end
```

Given `{ order_id: "123", tracking_number: "TRK-456" }`, both `order_id` and `tracking_number` receive the error. Passing zero fields is fine -- use `any_rule` if you need at least one.

### any_rule

At least one of the listed fields must be present. If none are present, **every** listed field receives the error message.

```ruby
class Orders::SearchAction
  include ActionFigure[:jsend]
  params_schema do
    optional(:order_id).filled(:string)
    optional(:tracking_number).filled(:string)
    optional(:customer_email).filled(:string)
  end

  rules do
    any_rule(:order_id, :tracking_number, :customer_email,
             "at least one search criterion is required")
  end

  def call(params:, **)
    # guaranteed at least one search field is present
  end
end
```

Given `{}`, all three fields receive the error. Given `{ order_id: "123", tracking_number: "TRK-456" }`, validation passes -- multiple present fields are fine.

### one_rule

Exactly one of the listed fields must be present. If zero or more than one are present, **every** listed field receives the error message.

```ruby
class Payments::CreateAction
  include ActionFigure[:jsend]
  params_schema do
    required(:amount).filled(:integer)
    optional(:credit_card_token).filled(:string)
    optional(:bank_account_id).filled(:string)
    optional(:wallet_id).filled(:string)
  end

  rules do
    one_rule(:credit_card_token, :bank_account_id, :wallet_id,
             "exactly one payment method is required")
  end

  def call(params:, **)
    # exactly one payment method is guaranteed
  end
end
```

Given `{ amount: 5000, credit_card_token: "tok_123", wallet_id: "wal_456" }`, all three payment method fields receive the error. Given `{ amount: 5000 }` with no payment method, all three also receive the error.

### all_rule

All listed fields must be present together, or all must be absent. A partial set causes **every** listed field to receive the error message.

```ruby
class Users::CreateAction
  include ActionFigure[:jsend]

  params_schema do
    required(:name).filled(:string)
    optional(:street).filled(:string)
    optional(:city).filled(:string)
    optional(:zip).filled(:string)
  end

  rules do
    all_rule(:street, :city, :zip,
             "address fields must be provided together or not at all")
  end

  def call(params:, **)
    # address is either complete or entirely absent
  end
end
```

Given `{ name: "Jane", street: "123 Main St" }`, all three address fields receive the error because only one of three is present. Given `{ name: "Jane" }` (none present) or `{ name: "Jane", street: "123 Main St", city: "Portland", zip: "97201" }` (all present), validation passes.

### implies_rule

If the antecedent field is present, the consequent field must also be present. **Both** the antecedent and consequent receive the error message on violation.

```ruby
class Payments::CreateAction
  include ActionFigure[:jsend]
  params_schema do
    required(:amount).filled(:integer)
    optional(:coupon_code).filled(:string)
    optional(:billing_email).filled(:string)
  end

  rules do
    implies_rule(:coupon_code, :billing_email,
                 "billing email is required when using a coupon")
  end

  def call(params:, **)
    # if coupon_code is present, billing_email is guaranteed present
  end
end
```

Given `{ amount: 2000, coupon_code: "SAVE20" }`, both `coupon_code` and `billing_email` receive the error. Given `{ amount: 2000, billing_email: "jane@example.com" }` (consequent without antecedent), validation passes -- the implication only applies when the antecedent is present.

---

## Extra Parameter Handling

By default, dry-validation silently strips any keys that are not declared in the schema. Your `#call` method only ever sees the declared fields:

```ruby
class Users::CreateAction
  include ActionFigure[:jsend]

  params_schema do
    required(:email).filled(:string)
  end

  def call(params:, **)
    params #=> { email: "jane@example.com" }
    # :admin was silently removed
  end
end

# Called with: { email: "jane@example.com", admin: true }
```

### whiny_extra_params

If you prefer to reject unexpected parameters outright, enable the `whiny_extra_params` configuration option:

```ruby
ActionFigure.configure do |config|
  config.whiny_extra_params = true
end
```

With this enabled, passing undeclared parameters returns an `UnprocessableContent` result with a 422 status. The error shape is consistent with all other validation errors:

```ruby
# Called with: { email: "jane@example.com", admin: true, role: "superuser" }

# Result errors:
{
  admin: ["is not allowed"],
  role: ["is not allowed"]
}
```

Each extra key receives its own `"is not allowed"` error message. This check runs **after** schema validation succeeds, so you will see schema errors or extra-param errors, never both at the same time.

---

## ActionController::Parameters

In Rails controllers, form data arrives as `ActionController::Parameters` rather than a plain `Hash`. ActionFigure handles this automatically: when it detects an object that responds to `to_unsafe_h`, it calls that method to convert it to a regular hash before validation.

This means you can pass `params` from a controller directly without calling `permit` or `to_h` yourself:

```ruby
class UsersController < ApplicationController
  def create
    render Users::CreateAction.call(
      params: params.require(:user),
      current_user: current_user
    )
  end
end
```

Plain hashes work identically -- ActionFigure only calls `to_unsafe_h` when the method is available. This makes actions easy to test without constructing `ActionController::Parameters` objects:

```ruby
result = Users::CreateAction.call(
  params: { email: "jane@example.com", name: "Jane" }
)
```
