# Integration Patterns

ActionFigure doesn't prescribe a serializer, authorization library, or pagination strategy. Pass any hash to `resource:` and it goes straight into the response envelope. This guide shows how popular gems plug into that pattern.

---

## Serialization

Every example below uses the same action — creating a user — so you can compare the serialization step directly.

### Plain Hashes

No gem required. Use `as_json`, `slice`, or build the hash by hand:

```ruby
class Users::CreateAction
  include ActionFigure[:jsend]

  params_schema do
    required(:user).hash do
      required(:email).filled(:string)
      required(:name).filled(:string)
    end
  end

  def call(params:, company:)
    user = company.users.create(params[:user])
    return UnprocessableContent(errors: user.errors.messages) if user.errors.any?

    Created(resource: user.as_json(only: %i[id name email]))
  end
end
```

For more control, build the hash yourself:

```ruby
def call(params:, company:)
  user = company.users.create(params[:user])
  return UnprocessableContent(errors: user.errors.messages) if user.errors.any?

  resource = { id: user.id, name: user.name, email: user.email, initials: user.name.split.map(&:first).join }
  Created(resource:)
end
```

`as_json` and hand-rolled hashes work well for simple cases. When serialization logic grows — conditional fields, nested associations, computed attributes — a dedicated serializer keeps it out of the action.

### Blueprinter

[Blueprinter](https://github.com/procore-oss/blueprinter) defines serialization with a declarative DSL:

```ruby
class UserBlueprint < Blueprinter::Base
  identifier :id
  fields :name, :email
end
```

```ruby
class Users::CreateAction
  include ActionFigure[:jsend]

  params_schema do
    required(:user).hash do
      required(:email).filled(:string)
      required(:name).filled(:string)
    end
  end

  def call(params:, company:)
    user = company.users.create(params[:user])
    return UnprocessableContent(errors: user.errors.messages) if user.errors.any?

    Created(resource: UserBlueprint.render_as_hash(user))
  end
end
```

Blueprinter supports views for different contexts:

```ruby
class UserBlueprint < Blueprinter::Base
  identifier :id
  fields :name, :email

  view :detailed do
    association :company, blueprint: CompanyBlueprint
    field :created_at
  end
end

# In the action:
resource = UserBlueprint.render_as_hash(user, view: :detailed)
```

### Alba

[Alba](https://github.com/okuramasafumi/alba) is a fast serializer with a flexible DSL:

```ruby
class UserResource
  include Alba::Resource

  attributes :id, :name, :email
end
```

```ruby
class Users::CreateAction
  include ActionFigure[:jsend]

  params_schema do
    required(:user).hash do
      required(:email).filled(:string)
      required(:name).filled(:string)
    end
  end

  def call(params:, company:)
    user = company.users.create(params[:user])
    return UnprocessableContent(errors: user.errors.messages) if user.errors.any?

    Created(resource: UserResource.new(user).to_h)
  end
end
```

Alba supports conditional attributes and nested resources:

```ruby
class UserResource
  include Alba::Resource

  attributes :id, :name, :email

  attribute :company do |user|
    CompanyResource.new(user.company).to_h
  end
end
```

### Oj Serializers

[Oj Serializers](https://github.com/ElMassimo/oj_serializers) is optimized for performance using Oj:

```ruby
class UserSerializer < Oj::Serializer
  attributes :id, :name, :email
end
```

```ruby
class Users::CreateAction
  include ActionFigure[:jsend]

  params_schema do
    required(:user).hash do
      required(:email).filled(:string)
      required(:name).filled(:string)
    end
  end

  def call(params:, company:)
    user = company.users.create(params[:user])
    return UnprocessableContent(errors: user.errors.messages) if user.errors.any?

    Created(resource: UserSerializer.one(user))
  end
end
```

For collections, use `many`:

```ruby
class Users::IndexAction
  include ActionFigure[:jsend]

  def call(company:, **)
    users = company.users.order(:name)
    resource = UserSerializer.many(users)
    Ok(resource:)
  end
end
```

---

## Authorization

Authorization gems work naturally with action classes. Inject the current user from the controller and call the authorization check during orchestration.

### Pundit

Call the [Pundit](https://github.com/varvet/pundit) policy directly inside the action:

```ruby
class Users::DestroyAction
  include ActionFigure[:jsend]

  params_schema do
    required(:id).filled(:integer)
  end

  def call(params:, current_user:)
    user = User.find(params[:id])
    unless UserPolicy.new(current_user, user).destroy?
      return Forbidden(errors: { base: ["not authorized to delete this user"] })
    end
    user.destroy!
    NoContent()
  end
end
```

```ruby
class UsersController < ApplicationController
  def destroy
    render Users::DestroyAction.call(params:, current_user: current_user)
  end
end
```

### CanCanCan

With [CanCanCan](https://github.com/CanCanCommunity/cancancan), build the ability from the current user:

```ruby
class Users::DestroyAction
  include ActionFigure[:jsend]

  params_schema do
    required(:id).filled(:integer)
  end

  def call(params:, current_user:)
    user = User.find(params[:id])
    if Ability.new(current_user).can?(:destroy, user)
      user.destroy!
      NoContent()
    else
      Forbidden(errors: { base: ["not authorized to delete this user"] })
    end
  end
end
```

```ruby
class UsersController < ApplicationController
  def destroy
    render Users::DestroyAction.call(params:, current_user: current_user)
  end
end
```

In both cases, authorization failures return a `Forbidden` response through the same formatter pipeline as everything else -- no exceptions, no controller rescue needed.

---

## Pagination

### Cursor Pagination

For paginated lists, accept cursor params and delegate the query logic to a service object. The action orchestrates -- the service does the heavy lifting:

```ruby
class Users::IndexAction
  include ActionFigure[:jsend]

  params_schema do
    optional(:cursor).filled(:integer)
    optional(:limit).filled(:integer)
  end

  def call(params:, company:, **)
    page = UserQuery.page(company.users, cursor: params[:cursor], limit: params[:limit] || 20)
    resource = UserSerializer.many(page.records)
    Ok(resource:, meta: { next_cursor: page.next_cursor })
  end
end
```

```ruby
class UsersController < ApplicationController
  def index
    render Users::IndexAction.call(params:, company: current_company)
  end
end
```

The action checks params, delegates to `UserQuery` for the actual query, and formats the response. `UserQuery` is a plain Ruby class that knows how to paginate -- the action doesn't need to.

### activerecord_cursor_paginate

The same pattern works with [activerecord_cursor_paginate](https://github.com/fatkodima/activerecord_cursor_paginate):

```ruby
class Users::IndexAction
  include ActionFigure[:jsend]

  params_schema do
    optional(:cursor).filled(:string)
    optional(:limit).filled(:integer)
  end

  def call(params:, company:, **)
    page = company.users
      .cursor_paginate(after: params[:cursor], limit: params[:limit] || 20, order: :name)
      .fetch
    resource = UserSerializer.many(page.records)
    Ok(resource:, meta: { next_cursor: page.next_cursor, has_next: page.has_next? })
  end
end
```

### Pagy

Or with [pagy](https://github.com/ddnexus/pagy):

```ruby
class Users::IndexAction
  include ActionFigure[:jsend]
  include Pagy::Backend

  def call(request:, company:, **)
    pagy, users = pagy(:keyset, company.users.order(:name), request:)
    resource = UserSerializer.many(users)
    Ok(resource:, meta: { next: pagy.next })
  end
end
```
