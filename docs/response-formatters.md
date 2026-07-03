# Response Formatters

## Overview

ActionFigure action classes return **render-ready hashes** from their response helpers. Each hash contains `:json` and `:status` keys that you pass directly to `render` in your controller:

```ruby
class UsersController < ApplicationController
  def create
    render Users::CreateAction.call(params:)
  end
end
```

The **formatter** determines the shape of the JSON envelope wrapping your data. ActionFigure ships with five built-in formatters: Default, JSend, JSON:API, Wrapped, and RFC 9457.

## Choosing a Format

You select a formatter when you include ActionFigure in your action class:

```ruby
# Explicit Default (Rails-style)
class Users::CreateAction
  include ActionFigure[:default]
end

# Explicit JSend
class Users::CreateAction
  include ActionFigure[:jsend]
end

# Explicit JSON:API
class Users::CreateAction
  include ActionFigure[:jsonapi]
end

# Explicit Wrapped
class Users::CreateAction
  include ActionFigure[:wrapped]
end

# Explicit RFC 9457
class Users::CreateAction
  include ActionFigure[:rfc_9457]
end

# Uses the configured default (Default unless changed)
class Users::CreateAction
  include ActionFigure
end
```

## Response Helpers

Every formatter implements the same twelve response helpers. Eleven return a hash with `:json` and `:status` keys. `NoContent` returns only `:status`.

| Helper                          | HTTP Status              | When to Use                                      |
|---------------------------------|--------------------------|--------------------------------------------------|
| `Ok(resource:, meta: nil)`      | `200 OK`                 | Successful read or update                        |
| `Created(resource:, meta: nil)` | `201 Created`            | Successful resource creation                     |
| `Accepted(resource: nil, meta: nil)` | `202 Accepted`      | Request accepted for background processing       |
| `NoContent()`                   | `204 No Content`         | Successful delete or action with no response body|
| `PaymentRequired(errors:)`      | `402 Payment Required`   | Business billing or quota constraint             |
| `Forbidden(errors:)`            | `403 Forbidden`          | Authorization failure                            |
| `NotFound(errors:)`             | `404 Not Found`          | Resource not found                               |
| `Conflict(errors:)`             | `409 Conflict`           | Resource state conflict or duplicate             |
| `Gone(errors:)`                 | `410 Gone`               | Resource permanently deleted (not just 404)      |
| `UnprocessableContent(errors:)` | `422 Unprocessable Content` | Validation failures                           |
| `Locked(errors:)`               | `423 Locked`             | Resource locked by another process               |
| `UnavailableForLegalReasons(errors:)` | `451 Unavailable For Legal Reasons` | Resource censored for legal/regional reasons |

`NoContent` is shared across all formatters and is defined in the base `Formatter` module. It returns `{ status: :no_content }` with no JSON body.

ActionFigure provides helpers for the status codes most commonly returned by action logic. General request-level concerns like authentication (`401 Unauthorized`) and malformed requests (`400 Bad Request`) are typically handled by controller-level middleware, `before_action` filters, or framework error handling rather than inside individual action classes.

## Default Format

The default formatter produces Rails-style responses: the resource is the top-level JSON on success, and errors live under an `"errors"` key on failure. This is the configured default format — bare `include ActionFigure` uses it unless you change `config.format`.

### Success Responses

The resource you pass becomes the entire JSON body with no wrapper.

**`Ok` -- returning a single resource:**

```ruby
def call(params:)
  user = User.find(params[:id])
  resource = UserBlueprint.render_as_hash(user)
  Ok(resource:)
end
```

```json
{
  "id": 1,
  "name": "Jane Doe",
  "email": "jane@example.com"
}
```

**`Created` -- returning a new resource:**

```ruby
def call(params:)
  user = User.create(params)
  return UnprocessableContent(errors: user.errors.messages) if user.errors.any?

  resource = UserBlueprint.render_as_hash(user)
  Created(resource:)
end
```

```json
{
  "id": 42,
  "name": "Jane Doe",
  "email": "jane@example.com"
}
```

**`Ok` -- with metadata:**

When `meta:` is provided, the response wraps the resource under a `"data"` key so that `"meta"` can sit alongside it:

```ruby
def call(params:)
  users = User.where(active: true).limit(20)
  Ok(resource: users, meta: { next_cursor: "abc123", total: 42 })
end
```

```json
{
  "data": [
    { "id": 1, "name": "Jane Doe" },
    { "id": 2, "name": "John Smith" }
  ],
  "meta": {
    "next_cursor": "abc123",
    "total": 42
  }
}
```

Without `meta:`, the resource is the entire body. With `meta:`, the response becomes `{ "data": resource, "meta": meta }`.

**`Accepted` -- with no resource:**

```ruby
def call(params:)
  OrderFulfillmentJob.perform_later(params[:order_id])
  Accepted()
end
```

```json
{}
```

**`Accepted` -- with a resource:**

```ruby
def call(params:)
  order = Order.find(params[:id])
  order.update(status: "processing")
  Accepted(resource: { order_id: order.id, status: order.status })
end
```

```json
{
  "order_id": 7,
  "status": "processing"
}
```

### Failure Responses

Failure responses place the error hash under an `"errors"` key. The `errors:` argument expects a hash where keys are field names and values are arrays of error messages — the same shape as `ActiveModel::Errors#messages`.

**`UnprocessableContent` -- validation errors:**

```ruby
def call(params:)
  user = User.new(params)
  return UnprocessableContent(errors: user.errors.messages) unless user.save
  resource = UserBlueprint.render_as_hash(user)
  Created(resource:)
end
```

```json
{
  "errors": {
    "email": ["has already been taken"],
    "name": ["can't be blank"]
  }
}
```

**`NotFound`:**

```ruby
def call(params:)
  user = User.find_by(id: params[:id])
  return NotFound(errors: { base: ["User not found"] }) unless user
  resource = UserBlueprint.render_as_hash(user)
  Ok(resource:)
end
```

```json
{
  "errors": {
    "base": ["User not found"]
  }
}
```

**`Forbidden`:**

```ruby
def call(params:)
  order = Order.find(params[:id])
  return Forbidden(errors: { base: ["You do not have access to this order"] }) unless authorized?(order)
  resource = OrderBlueprint.render_as_hash(order)
  Ok(resource:)
end
```

```json
{
  "errors": {
    "base": ["You do not have access to this order"]
  }
}
```

**`Conflict`:**

```ruby
def call(params:)
  return Conflict(errors: { email: ["already registered"] }) if User.exists?(email: params[:email])
  user = User.create(params)
  Created(resource: user)
end
```

```json
{
  "errors": {
    "email": ["already registered"]
  }
}
```

**`PaymentRequired`:**

```ruby
def call(params:, current_user:)
  return PaymentRequired(errors: { base: ["subscription expired"] }) if current_user.subscription_expired?
  Ok(resource: Dashboard.for(current_user))
end
```

```json
{
  "errors": {
    "base": ["subscription expired"]
  }
}
```

## JSend Format

The JSend formatter wraps responses in the [JSend specification](https://github.com/omniti-labs/jsend) envelope.

### Success Responses

Success responses use `"status": "success"` with a `"data"` key containing the resource.

**`Ok` -- returning a single resource:**

```ruby
def call(params:)
  user = User.find(params[:id])
  resource = UserBlueprint.render_as_hash(user)
  Ok(resource:)
end
```

```json
{
  "status": "success",
  "data": {
    "id": 1,
    "name": "Jane Doe",
    "email": "jane@example.com"
  }
}
```

**`Created` -- with metadata:**

```ruby
def call(params:)
  user = User.create(params)
  return UnprocessableContent(errors: user.errors.messages) if user.errors.any?

  resource = UserBlueprint.render_as_hash(user)
  Created(resource:, meta: { request_id: "abc-123" })
end
```

```json
{
  "status": "success",
  "data": {
    "id": 42,
    "name": "Jane Doe",
    "email": "jane@example.com"
  },
  "meta": {
    "request_id": "abc-123"
  }
}
```

**`Accepted` -- with no resource:**

```ruby
def call(params:)
  OrderFulfillmentJob.perform_later(params[:order_id])
  Accepted()
end
```

```json
{
  "status": "success"
}
```

**`Accepted` -- with a resource:**

```ruby
def call(params:)
  order = Order.find(params[:id])
  order.update(status: "processing")
  Accepted(resource: { order_id: order.id, status: order.status })
end
```

```json
{
  "status": "success",
  "data": {
    "order_id": 7,
    "status": "processing"
  }
}
```

### Failure Responses

Failure responses use `"status": "fail"` with a `"data"` key containing the error hash. The `errors:` argument expects a hash where keys are field names and values are arrays of error messages.

**`UnprocessableContent` -- validation errors:**

```ruby
def call(params:)
  user = User.new(params)
  return UnprocessableContent(errors: user.errors.messages) unless user.save
  resource = UserBlueprint.render_as_hash(user)
  Created(resource:)
end
```

```json
{
  "status": "fail",
  "data": {
    "email": ["has already been taken"],
    "name": ["can't be blank"]
  }
}
```

**`NotFound`:**

```ruby
def call(params:)
  user = User.find_by(id: params[:id])
  return NotFound(errors: { base: ["User not found"] }) unless user
  resource = UserBlueprint.render_as_hash(user)
  Ok(resource:)
end
```

```json
{
  "status": "fail",
  "data": {
    "base": ["User not found"]
  }
}
```

**`Forbidden`:**

```ruby
def call(params:)
  order = Order.find(params[:id])
  return Forbidden(errors: { base: ["You do not have access to this order"] }) unless authorized?(order)
  resource = OrderBlueprint.render_as_hash(order)
  Ok(resource:)
end
```

```json
{
  "status": "fail",
  "data": {
    "base": ["You do not have access to this order"]
  }
}
```

**`Conflict`:**

```ruby
def call(params:)
  return Conflict(errors: { email: ["already registered"] }) if User.exists?(email: params[:email])
  user = User.create(params)
  Created(resource: user)
end
```

```json
{
  "status": "fail",
  "data": {
    "email": ["already registered"]
  }
}
```

**`PaymentRequired`:**

```ruby
def call(params:, current_user:)
  return PaymentRequired(errors: { base: ["subscription expired"] }) if current_user.subscription_expired?
  Ok(resource: Dashboard.for(current_user))
end
```

```json
{
  "status": "fail",
  "data": {
    "base": ["subscription expired"]
  }
}
```

## Wrapped Format

The Wrapped formatter places every response in a uniform `{ data:, errors:, status: }` envelope. Success responses use `"status": "success"` and failure responses use `"status": "error"`.

### Success Responses

**`Ok` -- returning a single resource:**

```ruby
def call(params:)
  user = User.find(params[:id])
  resource = UserBlueprint.render_as_hash(user)
  Ok(resource:)
end
```

```json
{
  "data": {
    "id": 1,
    "name": "Jane Doe",
    "email": "jane@example.com"
  },
  "errors": null,
  "status": "success"
}
```

**`Created` -- with metadata:**

```ruby
def call(params:)
  user = User.create(params)
  return UnprocessableContent(errors: user.errors.messages) if user.errors.any?

  resource = UserBlueprint.render_as_hash(user)
  Created(resource:, meta: { request_id: "abc-123" })
end
```

```json
{
  "data": {
    "id": 42,
    "name": "Jane Doe",
    "email": "jane@example.com"
  },
  "errors": null,
  "status": "success",
  "meta": {
    "request_id": "abc-123"
  }
}
```

**`Accepted` -- with no resource:**

```ruby
def call(params:)
  OrderFulfillmentJob.perform_later(params[:order_id])
  Accepted()
end
```

```json
{
  "data": null,
  "errors": null,
  "status": "success"
}
```

**`Accepted` -- with a resource:**

```ruby
def call(params:)
  order = Order.find(params[:id])
  order.update(status: "processing")
  Accepted(resource: { order_id: order.id, status: order.status })
end
```

```json
{
  "data": {
    "order_id": 7,
    "status": "processing"
  },
  "errors": null,
  "status": "success"
}
```

### Failure Responses

Failure responses use `"status": "error"` with the error hash under `"errors"` and `"data"` set to `null`.

**`UnprocessableContent` -- validation errors:**

```ruby
def call(params:)
  user = User.new(params)
  return UnprocessableContent(errors: user.errors.messages) unless user.save
  resource = UserBlueprint.render_as_hash(user)
  Created(resource:)
end
```

```json
{
  "data": null,
  "errors": {
    "email": ["has already been taken"],
    "name": ["can't be blank"]
  },
  "status": "error"
}
```

**`NotFound`:**

```ruby
def call(params:)
  user = User.find_by(id: params[:id])
  return NotFound(errors: { base: ["User not found"] }) unless user
  resource = UserBlueprint.render_as_hash(user)
  Ok(resource:)
end
```

```json
{
  "data": null,
  "errors": {
    "base": ["User not found"]
  },
  "status": "error"
}
```

**`Forbidden`:**

```ruby
def call(params:)
  order = Order.find(params[:id])
  return Forbidden(errors: { base: ["You do not have access to this order"] }) unless authorized?(order)
  resource = OrderBlueprint.render_as_hash(order)
  Ok(resource:)
end
```

```json
{
  "data": null,
  "errors": {
    "base": ["You do not have access to this order"]
  },
  "status": "error"
}
```

**`Conflict`:**

```ruby
def call(params:)
  return Conflict(errors: { email: ["already registered"] }) if User.exists?(email: params[:email])
  user = User.create(params)
  Created(resource: user)
end
```

```json
{
  "data": null,
  "errors": {
    "email": ["already registered"]
  },
  "status": "error"
}
```

**`PaymentRequired`:**

```ruby
def call(params:, current_user:)
  return PaymentRequired(errors: { base: ["subscription expired"] }) if current_user.subscription_expired?
  Ok(resource: Dashboard.for(current_user))
end
```

```json
{
  "data": null,
  "errors": {
    "base": ["subscription expired"]
  },
  "status": "error"
}
```

## JSON:API Format

The JSON:API formatter structures responses according to the [JSON:API specification](https://jsonapi.org/).

### Success Responses

Success responses place the resource under a `"data"` key. ActiveRecord objects are automatically serialized into the `type` / `id` / `attributes` structure (see [ActiveRecord Serialization](#activerecord-serialization-jsonapi) below).

**`Ok` -- returning a single resource:**

```ruby
def call(params:)
  user = User.find(params[:id])
  Ok(resource: user)
end
```

```json
{
  "data": {
    "type": "user",
    "id": "1",
    "attributes": {
      "name": "Jane Doe",
      "email": "jane@example.com",
      "created_at": "2026-01-15T09:30:00Z",
      "updated_at": "2026-03-10T14:22:00Z"
    }
  }
}
```

**`Created` -- with metadata:**

```ruby
def call(params:)
  order = Order.create(params)
  return UnprocessableContent(errors: order.errors.messages) if order.errors.any?

  Created(resource: order, meta: { total_orders: Order.count })
end
```

```json
{
  "data": {
    "type": "order",
    "id": "87",
    "attributes": {
      "total": "49.99",
      "status": "pending",
      "created_at": "2026-03-23T12:00:00Z",
      "updated_at": "2026-03-23T12:00:00Z"
    }
  },
  "meta": {
    "total_orders": 12
  }
}
```

**`Ok` -- returning a collection:**

```ruby
def call(params:)
  users = User.where(active: true).limit(2)
  Ok(resource: users)
end
```

```json
{
  "data": [
    {
      "type": "user",
      "id": "1",
      "attributes": {
        "name": "Jane Doe",
        "email": "jane@example.com",
        "created_at": "2026-01-15T09:30:00Z",
        "updated_at": "2026-03-10T14:22:00Z"
      }
    },
    {
      "type": "user",
      "id": "2",
      "attributes": {
        "name": "John Smith",
        "email": "john@example.com",
        "created_at": "2026-02-20T11:00:00Z",
        "updated_at": "2026-03-18T08:45:00Z"
      }
    }
  ]
}
```

**`Accepted` -- with no resource:**

```ruby
def call(params:)
  OrderFulfillmentJob.perform_later(params[:order_id])
  Accepted()
end
```

```json
{}
```

### Error Responses

Error responses use the `"errors"` key with an array of error objects. Each error object contains `status`, `detail`, and `source.pointer`.

**`UnprocessableContent` -- validation errors:**

```ruby
def call(params:)
  user = User.new(params)
  return UnprocessableContent(errors: user.errors.messages) unless user.save
  Created(resource: user)
end
```

Given `errors.messages` of `{ email: ["has already been taken"], name: ["can't be blank", "is too short"] }`:

```json
{
  "errors": [
    {
      "status": "422",
      "detail": "has already been taken",
      "source": { "pointer": "/data/attributes/email" }
    },
    {
      "status": "422",
      "detail": "can't be blank",
      "source": { "pointer": "/data/attributes/name" }
    },
    {
      "status": "422",
      "detail": "is too short",
      "source": { "pointer": "/data/attributes/name" }
    }
  ]
}
```

Note that multiple messages on the same field produce **separate error objects**, each with its own `detail`.

**`NotFound` -- with `:base` errors:**

```ruby
def call(params:)
  user = User.find_by(id: params[:id])
  return NotFound(errors: { base: ["User not found"] }) unless user
  Ok(resource: user)
end
```

```json
{
  "errors": [
    {
      "status": "404",
      "detail": "User not found",
      "source": { "pointer": "/data" }
    }
  ]
}
```

Errors keyed under `:base` receive the pointer `"/data"`. Field-level errors receive `"/data/attributes/{field}"`.

**`Forbidden`:**

```ruby
def call(params:)
  order = Order.find(params[:id])
  return Forbidden(errors: { base: ["You do not have access to this order"] }) unless authorized?(order)
  Ok(resource: order)
end
```

```json
{
  "errors": [
    {
      "status": "403",
      "detail": "You do not have access to this order",
      "source": { "pointer": "/data" }
    }
  ]
}
```

**`Conflict`:**

```ruby
def call(params:)
  return Conflict(errors: { email: ["already registered"] }) if User.exists?(email: params[:email])
  user = User.create(params)
  Created(resource: user)
end
```

```json
{
  "errors": [
    {
      "status": "409",
      "detail": "already registered",
      "source": { "pointer": "/data/attributes/email" }
    }
  ]
}
```

**`PaymentRequired`:**

```ruby
def call(params:, current_user:)
  return PaymentRequired(errors: { base: ["subscription expired"] }) if current_user.subscription_expired?
  Ok(resource: Dashboard.for(current_user))
end
```

```json
{
  "errors": [
    {
      "status": "402",
      "detail": "subscription expired",
      "source": { "pointer": "/data" }
    }
  ]
}
```

## ActiveRecord Serialization (JSON:API)

The JSON:API formatter includes automatic serialization for ActiveRecord objects via the `Resource` class.

### Detection Rules

The serializer inspects the object you pass as `resource:` and applies different strategies:

| Object type                           | Behavior                                            |
|---------------------------------------|-----------------------------------------------------|
| Responds to `.attributes` and `.class.model_name.element` (e.g., AR model) | Serialized into `{ type, id, attributes }` |
| `Hash`                                | Passed through unchanged                            |
| Responds to `.each` (e.g., Array, AR::Relation) | Each element serialized individually      |
| Anything else                         | Passed through unchanged                            |

### How ActiveRecord Models Are Serialized

The serializer uses the ActiveModel `model_name` API to determine the resource type. Given a `User` record with `id: 1, name: "Jane Doe", email: "jane@example.com"`:

- **`type`** is derived from `resource.class.model_name.element`, producing the singular, snake_case model name (e.g., `"user"` for `User`, `"line_item"` for `LineItem`).
- **`id`** is always cast to a string (`"1"`, not `1`), per the JSON:API specification.
- **`attributes`** contains all model attributes **except** `"id"`, since the id is already a top-level member.

```json
{
  "type": "user",
  "id": "1",
  "attributes": {
    "name": "Jane Doe",
    "email": "jane@example.com",
    "created_at": "2026-01-15T09:30:00Z",
    "updated_at": "2026-03-10T14:22:00Z"
  }
}
```

### Hash Passthrough

When you pass a `Hash` as the resource, the JSON:API formatter returns it unchanged. This is useful when you are using a dedicated serialization library like Blueprinter or Alba and want to control the shape yourself:

```ruby
def call(params:)
  user = User.find(params[:id])
  Ok(resource: UserBlueprint.render_as_hash(user))
end
```

The hash is placed directly under the `"data"` key with no further transformation.

### Collections

Arrays and ActiveRecord::Relations are mapped element-by-element. Each element goes through the same detection rules described above, so a collection of AR models produces an array of `{ type, id, attributes }` objects.

```ruby
def call(params:)
  orders = Order.where(user_id: params[:user_id]).order(created_at: :desc)
  Ok(resource: orders, meta: { count: orders.size })
end
```

```json
{
  "data": [
    {
      "type": "order",
      "id": "87",
      "attributes": {
        "total": "49.99",
        "status": "shipped",
        "created_at": "2026-03-20T10:00:00Z",
        "updated_at": "2026-03-22T16:30:00Z"
      }
    },
    {
      "type": "order",
      "id": "63",
      "attributes": {
        "total": "129.00",
        "status": "delivered",
        "created_at": "2026-02-14T08:15:00Z",
        "updated_at": "2026-02-18T11:45:00Z"
      }
    }
  ],
  "meta": {
    "count": 2
  }
}
```

## RFC 9457 Format

The RFC 9457 formatter renders errors as [RFC 9457](https://www.rfc-editor.org/rfc/rfc9457) problem documents (`Content-Type: application/problem+json`). Success responses use the same `type`/`title` vocabulary, though RFC 9457 itself only covers errors.

### Success Responses

Success responses place the resource under a key derived from its class name and carry `type` and `title` members.

**`Created` -- returning a model resource:**

```ruby
def call(params:)
  user = User.create(params)
  return UnprocessableContent(errors: user.errors.messages) if user.errors.any?

  Created(
    resource: user,
    type: "https://api.example.com/success/user-created",
    title: "User created"
  )
end
```

```json
{
  "type": "https://api.example.com/success/user-created",
  "title": "User created",
  "user": { "id": 42, "name": "Jane Doe", "email": "jane@example.com" }
}
```

Without explicit `type:` and `title:`, the formatter derives them from the resource class and status — `User` + `Created` → `type: "user-created"`, `title: "User created"`. For `Ok`, `User` + `Ok` → `type: "user-ok"`, `title: "User ok"` — deliberately awkward. Pass explicit values your clients can rely on.

Hash and primitive resources fall back to the key `data` and the name `resource`:

```ruby
Created(resource: { order_id: 7, status: "queued" })
# -> type: "resource-created", title: "Resource created", data: { ... }
```

Override the derived name with `as:`:

```ruby
Created(resource: some_hash, as: :order)
# -> type: "order-created", title: "Order created", order: { ... }
```

**`Accepted` -- with no resource:**

```ruby
def call(params:)
  OrderFulfillmentJob.perform_later(params[:order_id])
  Accepted()
end
```

```json
{
  "type": "resource-accepted",
  "title": "Resource accepted"
}
```

### Failure Responses

Failure responses produce RFC 9457 problem documents. All members except `type`, `title`, and `status` are optional.

**`UnprocessableContent` -- validation errors:**

`UnprocessableContent` defaults to `type: "unprocessable-content-error"`, so schema validation failures work without any configuration:

```ruby
def call(params:)
  user = User.new(params)
  return UnprocessableContent(errors: user.errors.messages) unless user.save
  resource = UserBlueprint.render_as_hash(user)
  Created(resource:, type: "https://api.example.com/success/user-created", title: "User created")
end
```

```json
{
  "type": "unprocessable-content-error",
  "title": "Unprocessable Content",
  "status": 422,
  "errors": {
    "email": ["has already been taken"],
    "name": ["can't be blank"]
  }
}
```

Override `type:` and `title:` when you want a domain-specific URI:

```ruby
UnprocessableContent(
  errors: user.errors.messages,
  type: "https://api.example.com/problems/validation-error",
  title: "Validation failed"
)
```

**`NotFound` -- with `detail` and `instance`:**

```ruby
def call(params:)
  user = User.find_by(id: params[:id])
  return NotFound(
    type: "https://api.example.com/problems/user-not-found",
    title: "User not found",
    detail: "No user with id #{params[:id]} exists.",
    instance: "/users/#{params[:id]}"
  ) unless user
  Ok(resource: user, type: "https://api.example.com/success/user-ok", title: "User found")
end
```

```json
{
  "type": "https://api.example.com/problems/user-not-found",
  "title": "User not found",
  "status": 404,
  "detail": "No user with id 99 exists.",
  "instance": "/users/99"
}
```

Extra kwargs become extension members in the problem document:

```ruby
PaymentRequired(
  type: "https://api.example.com/problems/quota-exceeded",
  title: "Quota exceeded",
  balance: 0,
  limit: 100
)
```

```json
{
  "type": "https://api.example.com/problems/quota-exceeded",
  "title": "Quota exceeded",
  "status": 402,
  "balance": 0,
  "limit": 100
}
```

`UnprocessableContent` defaults to `type: "unprocessable-content-error"`. All other error helpers derive `type` from the action class and status — `Projects::FindAction` + `NotFound` → `"projects-find-not-found-error"`. Provide a stable URI; the default is intentionally unattractive.

## The `meta:` Keyword

The `meta:` keyword argument is available on `Ok`, `Created`, and `Accepted`. It accepts any hash, which is included as a top-level `"meta"` key in all five formatters. When `meta:` is `nil` (the default), the key is omitted entirely from the response. In the default formatter, providing `meta:` wraps the response in `{ "data": resource, "meta": meta }` — without `meta:`, the resource is the entire body.

Common uses for `meta:`:

- **Pagination cursors** for keyset pagination
- **Result counts** for listing endpoints
- **Request tracing** identifiers

```ruby
def call(params:)
  users = User.where("id > ?", params[:after]).limit(20)
  last_user = users.last

  Ok(
    resource: users,
    meta: {
      next_cursor: last_user&.id,
      count: users.size
    }
  )
end
```

**Default output:**

```json
{
  "data": [
    { "id": 5, "name": "Alice Yu", "email": "alice@example.com" },
    { "id": 6, "name": "Bob Park", "email": "bob@example.com" }
  ],
  "meta": {
    "next_cursor": 6,
    "count": 2
  }
}
```

**JSend output:**

```json
{
  "status": "success",
  "data": [
    { "id": 5, "name": "Alice Yu", "email": "alice@example.com" },
    { "id": 6, "name": "Bob Park", "email": "bob@example.com" }
  ],
  "meta": {
    "next_cursor": 6,
    "count": 2
  }
}
```

**Wrapped output:**

```json
{
  "data": [
    { "id": 5, "name": "Alice Yu", "email": "alice@example.com" },
    { "id": 6, "name": "Bob Park", "email": "bob@example.com" }
  ],
  "errors": null,
  "status": "success",
  "meta": {
    "next_cursor": 6,
    "count": 2
  }
}
```

**JSON:API output:**

```json
{
  "data": [
    {
      "type": "user",
      "id": "5",
      "attributes": {
        "name": "Alice Yu",
        "email": "alice@example.com"
      }
    },
    {
      "type": "user",
      "id": "6",
      "attributes": {
        "name": "Bob Park",
        "email": "bob@example.com"
      }
    }
  ],
  "meta": {
    "next_cursor": 6,
    "count": 2
  }
}
```
