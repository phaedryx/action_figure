# HTTP 4xx Status Codes

Rows in **bold** are status codes with built-in formatter methods — action classes can return these directly via helpers like `NotFound(errors:)` or `Conflict(errors:)`. All other 4xx codes are handled outside action classes by the perimeter (middleware, router, Rack, or infrastructure).

| Status | Name                             | Category  | Responsibility  | Description / Logic Example                                          |
|--------|----------------------------------|-----------|-----------------|----------------------------------------------------------------------|
| 400    | Bad Request                      | Perimeter | Controller/Rack | Malformed syntax or missing top-level structure.                     |
| 401    | Unauthorized                     | Perimeter | Middleware/Auth  | Authentication failed or missing credentials.                        |
| **402** | **Payment Required**            | **Domain** | **Action Class** | **Business state: "Subscription overdue" or "Quota exceeded."**     |
| **403** | **Forbidden**                   | **Domain** | **Action Class** | **Authenticated, but lacks permissions for this specific task.**    |
| **404** | **Not Found**                   | **Domain** | **Action Class** | **The requested resource ID does not exist in the database.**       |
| 405    | Method Not Allowed               | Perimeter | Rails Router     | Sending a POST to a GET route.                                       |
| 406    | Not Acceptable                   | Perimeter | Controller       | Client requested a format (e.g., XML) the server won't provide.     |
| 407    | Proxy Auth Required              | Perimeter | Infrastructure   | Similar to 401, but for a proxy server.                              |
| 408    | Request Timeout                  | Perimeter | Server/Nginx     | The client took too long to send the request.                        |
| **409** | **Conflict**                    | **Domain** | **Action Class** | **Resource already exists, or the state is in conflict.**           |
| **410** | **Gone**                        | **Domain** | **Action Class** | **The resource is permanently deleted (not just 404).**             |
| 411    | Length Required                  | Perimeter | Server/Rack      | The request didn't specify a Content-Length.                         |
| 412    | Precondition Failed              | Perimeter | Controller/Rack  | If-Match headers don't match (usually for caching).                  |
| 413    | Payload Too Large                | Perimeter | Server/Nginx     | The request body is bigger than the server allows.                   |
| 414    | URI Too Long                     | Perimeter | Server/Nginx     | The URL is too long for the server to process.                       |
| 415    | Unsupported Media Type           | Perimeter | Controller       | Sending text/plain instead of application/json.                      |
| 416    | Range Not Satisfiable            | Perimeter | Server/Rack      | Invalid Range header (usually for file downloads).                   |
| 417    | Expectation Failed               | Perimeter | Server           | The server can't meet the Expect header requirements.                |
| 418    | I'm a teapot                     | Domain    | Action Class     | An IETF April Fools joke (rarely used in production).                |
| 421    | Misdirected Request              | Perimeter | Infrastructure   | The server can't produce a response for this connection.             |
| **422** | **Unprocessable Content**       | **Domain** | **Action Class** | **Semantic errors (validation, business rules).**                   |
| **423** | **Locked**                      | **Domain** | **Action Class** | **The resource is being accessed by another process.**              |
| 424    | Failed Dependency                | Domain    | Action Class     | The request failed due to a failure of a previous request.           |
| 425    | Too Early                        | Perimeter | Server/Rack      | The server is unwilling to process a request that might be replayed. |
| 426    | Upgrade Required                 | Perimeter | Server/Rack      | The client must switch to a different protocol (e.g., TLS).          |
| 428    | Precondition Required            | Perimeter | Controller/Rack  | The server requires the request to be conditional.                   |
| 429    | Too Many Requests                | Perimeter | Rack::Attack     | Infrastructure-level rate limiting (IP-based, etc.).                 |
| 431    | Request Header Fields Too Large  | Perimeter | Server/Rack      | HTTP headers are too large.                                          |
| **451** | **Unavailable For Legal Reasons** | **Domain** | **Action Class** | **Resource censored/blocked for legal/regional reasons.**          |

Any other status — including 5xx codes such as 502 Bad Gateway — can be added with `ActionFigure.register_error(:BadGateway, :bad_gateway)`. The status symbol is validated against Rack's status table at registration, so a typo raises `ArgumentError` at boot. 5xx codes are a deliberate opt-out from the domain/perimeter split and are not built in by default.
