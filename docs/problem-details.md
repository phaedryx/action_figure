# Problem Details (RFC 9457)

## Overview

The `:rfc_9457` formatter renders errors as [RFC 9457](https://www.rfc-editor.org/rfc/rfc9457) problem documents with `Content-Type: application/problem+json`. Success responses mirror the same `type`/`title` vocabulary, though RFC 9457 itself only specifies error documents.

```ruby
class Projects::FindAction
  include ActionFigure[:rfc_9457]

  def show(params:)
    project = Project.find_by(id: params[:id])
    return NotFound(
      errors: { id: ["not found"] },
      type: "https://api.example.com/problems/project-not-found",
      title: "Project not found",
      detail: "No project with id #{params[:id]} exists.",
      instance: "/projects/#{params[:id]}"
    ) unless project

    Ok(resource: project, type: "project-found", title: "Project found")
  end
end
```

## Error Responses

Error helpers (`NotFound`, `Conflict`, etc.) produce a problem document:

| Member     | Default                                                    | Override kwarg |
|------------|------------------------------------------------------------|----------------|
| `type`     | `"<action-class>-<status>-error"`; `UnprocessableContent` uses `"unprocessable-content-error"` (see Defaults below) | `type:` |
| `title`    | HTTP status phrase, e.g. `"Not Found"`                     | `title:`       |
| `status`   | Numeric HTTP code, e.g. `404`                              | —              |
| `detail`   | Omitted                                                    | `detail:`      |
| `instance` | Omitted                                                    | `instance:`    |
| `errors`   | Extension member; omitted when nil                         | `errors:`      |

Any additional kwargs become extension members.

The render hash includes `content_type: "application/problem+json"`. Rails honors this directly; a plain Rack app can read the key.

### Defaults

`UnprocessableContent` has a fixed default type of `"unprocessable-content-error"`. The framework calls this helper automatically on schema validation failure, so a stable type is provided without configuration:

```ruby
# Schema failure — type is already "unprocessable-content-error":
UnprocessableContent(errors: result.errors.to_h)

# Override when you want a domain-specific URI:
UnprocessableContent(
  errors: user.errors.messages,
  type: "https://api.example.com/problems/validation-error",
  title: "Validation failed"
)
```

All other error helpers derive `type` mechanically from the action class and HTTP status — `Projects::FindAction` + `NotFound` → `"projects-find-not-found-error"`. This is intentionally awkward. The RFC recommends a stable URI, and your API clients deserve one:

```ruby
# Awkward default — a signal to replace it:
# type: "projects-find-not-found-error"

# What you should write instead:
NotFound(
  type: "https://api.example.com/problems/project-not-found",
  title: "Project not found",
  errors: { id: ["not found"] }
)
```

## Success Responses

Success helpers (`Ok`, `Created`, `Accepted`) build a mirrored vocabulary:

| Member            | Default                                            | Override kwarg |
|-------------------|----------------------------------------------------|----------------|
| `type`            | `"<resource-name>-<status>"` (see below)           | `type:`        |
| `title`           | `"<Resource name> <status>"` (see below)           | `title:`       |
| `<resource-key>`  | Resource under its class-derived name or `data`    | `as:`          |
| `meta`            | Omitted when nil                                   | `meta:`        |

The resource key and name derive from the resource's class:

```ruby
Created(resource: user)       # User instance → key :user
# type: "user-created", title: "User created", user: { ... }

Created(resource: some_hash)  # Hash → key :data
# type: "resource-created", title: "Resource created", data: { ... }

Created(resource: h, as: :project)  # explicit override
# type: "project-created", title: "Project created", project: { ... }
```

`as:`, `type:`, and `title:` can be used independently — `as:` drives the resource key and the derived defaults; `type:` and `title:` override only their own member.

Trailing `Action` is stripped from class names: `Projects::CreateAction` → `"projects-create"`.

`Ok(resource: user)` defaults to `type: "user-ok"` / `title: "User ok"` — deliberately awkward for the same reason as error defaults. Pass `type:` and `title:` to give your clients something meaningful.

Success responses use plain `application/json` (no `content_type:` key).

`NoContent` returns `{ status: :no_content }` with no body — inherited from the base formatter.

## Registering Additional Error Statuses

`ActionFigure.register_error` works the same way as with any other formatter. Registered error helpers automatically use `error_response`, so they produce problem documents in `:rfc_9457` action classes without any extra configuration.

## Custom `error_response` Contract

If you write a custom formatter that you want to compose with RFC 9457 style, note that `error_response` now receives `errors: nil, status:, **extras`. Accept `**extras` to let `detail:`, `instance:`, and extension members flow through.
