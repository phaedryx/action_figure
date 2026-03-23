# Actions

## Overview

An ActionFigure action class is a single-purpose operation. Each class encapsulates one thing your application does -- creating a user, searching orders, processing a refund. This guide covers how to declare action classes, customize their entry points, inject dependencies, and wire them into your controllers.

---

## The Default: `call`

Every action class gets a `.call` class method when it includes ActionFigure. It instantiates the class, runs the validation pipeline (if `params:` is provided), and delegates to the instance-level `#call` method.

```ruby
class Users::Create
  include ActionFigure[:jsend]

  params_schema do
    required(:email).filled(:string)
    required(:name).filled(:string)
  end

  def call(params:, company:, **)
    user = company.users.create!(params)
    Ok(resource: user)
  end
end
```

Wire it into a controller by passing `params:` and any additional context:

```ruby
class UsersController < ApplicationController
  def create
    render Users::Create.call(params: params.require(:user), company: current_company)
  end
end
```

---

## Custom Entry Points

Some actions have a name that reads better than `.call`. The `entry_point` macro declares an alternative class-level method name:

```ruby
class Orders::Search
  include ActionFigure[:jsend]

  entry_point :search

  params_schema do
    optional(:order_id).filled(:string)
    optional(:tracking_number).filled(:string)
    optional(:status).filled(:string)
  end

  def search(params:, company:, **)
    orders = company.orders
    orders = orders.where(id: params[:order_id])                 if params[:order_id]
    orders = orders.where(tracking_number: params[:tracking_number]) if params[:tracking_number]
    orders = orders.where(status: params[:status])               if params[:status]
    Ok(resource: orders)
  end
end
```

Call it from a controller using the declared name:

```ruby
class OrdersController < ApplicationController
  def index
    render Orders::Search.search(params: params.permit!, company: current_company)
  end
end
```

### How it works

- The instance method must match the declared entry point name (`:search` declares `.search` and expects `#search`).
- The full validation pipeline still runs through the custom entry point -- `params_schema` and `rules` are applied before your method is invoked.
- Calling `.call` on a class that declares a custom entry point raises a `NoMethodError` with a helpful message:

  ```
  NoMethodError: undefined method 'call' for Orders::Search (use 'search' instead)
  ```

- Only one entry point per class is allowed. A second `entry_point` declaration raises an `ArgumentError`:

  ```
  ArgumentError: entry_point already defined as 'search' -- each action class may declare only one entry point
  ```

---

## No-Params Actions

Actions that don't need validated input simply omit `params_schema`. Instead of accepting `params:`, they receive only the keyword arguments you pass from the controller.

```ruby
class Users::Destroy
  include ActionFigure[:jsend]

  def call(user_id:, current_user:, **)
    user = User.find(user_id)
    authorize!(current_user, user)
    user.destroy!
    NoContent()
  end
end
```

```ruby
class UsersController < ApplicationController
  def destroy
    render Users::Destroy.call(user_id: params[:id], current_user: current_user)
  end
end
```

Because no `params_schema` is defined, the validation pipeline is skipped entirely. If you accidentally pass `params:` to an action that has no schema, ActionFigure raises immediately:

```
ArgumentError: params: passed but no params_schema defined
```

---

## Dependency Injection

Non-`params:` keyword arguments pass through to the instance method untouched. This is how you inject context from the controller -- the current user, the tenant, a logger, or any other collaborator -- without any special DSL.

```ruby
class Users::Create
  include ActionFigure[:jsend]

  params_schema do
    required(:email).filled(:string)
    required(:name).filled(:string)
  end

  def call(params:, company:, current_user:, **)
    user = company.users.create!(params.merge(invited_by: current_user))
    Ok(resource: user)
  end
end
```

```ruby
class UsersController < ApplicationController
  def create
    render Users::Create.call(
      params: params.require(:user),
      company: current_company,
      current_user: current_user
    )
  end
end
```

The double-splat (`**`) in the method signature is a good habit -- it lets you add new injected dependencies at the call site without changing every action that doesn't need them.

---

## API Versioning

The `api_version` class macro attaches version metadata to an action class.

```ruby
class Users::Create
  include ActionFigure[:jsend]

  api_version "2.0"

  params_schema do
    required(:email).filled(:string)
    required(:name).filled(:string)
  end

  def call(params:, **)
    user = User.create!(params)
    Ok(resource: user)
  end
end
```

### Reading the version

Call `api_version` with no arguments to read the stored value:

```ruby
Users::Create.api_version  #=> "2.0"
```

Inside an action instance, access it through the class:

```ruby
def call(params:, **)
  if self.class.api_version == "2.0"
    # v2 behavior
  end
end
```

### Defaults

If no `api_version` is declared on a class, it returns `nil` by default. You can set a global default through configuration:

```ruby
ActionFigure.configure do |config|
  config.api_version = "1.0"
end
```

A class-level declaration always takes precedence over the global default. Version values are independent per class -- they are not inherited by subclasses.

---

## File Conventions

Place action classes in `app/actions/` so Rails autoloading picks them up. Name them `ResourceName::Verb`:

```
app/actions/
  users/
    create.rb
    destroy.rb
    update.rb
  orders/
    search.rb
    cancel.rb
  payments/
    refund.rb
```

This maps to class names like `Users::Create`, `Orders::Search`, and `Payments::Refund`.

---

## Design Constraints

Action classes are intentionally flat. The class-level state that powers `params_schema`, `rules`, and `entry_point` is stored in **class-level instance variables** and is **not inherited** by subclasses. If you subclass an action, the child class starts with a blank slate -- no schema, no rules, no custom entry point.

This is by design. Each action class should be a self-contained, independently readable unit. If you find yourself wanting to share behavior across actions, extract shared logic into plain Ruby modules or service objects and compose them explicitly.
