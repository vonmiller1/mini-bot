# DreamFactory Mini

**Instant REST APIs from your database. Nothing else.**

DF Mini is a stripped-down DreamFactory that connects to your database and gives you a full REST API with Swagger docs. No enterprise auth, no scripting engine, no message queues — just your data as an API. There is no admin UI — everything is done via the API itself.

## Quick Start

```bash
ADMIN_EMAIL=you@yourcompany.com ADMIN_PASSWORD=YourSecurePassword123 docker compose up -d
```

That's it. API is at `http://localhost:8088/api/v2`.

> **Note:** First boot runs database migration (~4 seconds).

## What's Included

- **PostgreSQL** connector
- **MySQL / MariaDB** connector
- **SQL Server** connector
- **SQLite** connector
- **Remote Web Services (RWS)** — proxy any HTTP/REST API
- **SOAP** connector
- **Auto-generated REST endpoints** for every table
- **Swagger/OpenAPI docs** at `/api/v2/api_docs`
- **JWT session auth + API key auth**
- **SQLite system database** (zero config)
- **File-based cache** (no Redis needed)

## What's NOT Included

Everything else. No MongoDB, no AWS, no SAML, no LDAP, no scripting, no scheduler, no email, no admin UI. If you need those, use [full DreamFactory](https://github.com/dreamfactorysoftware/dreamfactory).

## Usage

DF Mini has no admin UI. You manage everything through the REST API. Here's the full workflow.

### 1. Log In

```bash
TOKEN=$(curl -s -X POST http://localhost:8088/api/v2/system/admin/session \
  --data-urlencode "email=you@yourdomain.com" \
  --data-urlencode "password=YourSecurePassword123" \
  | jq -r '.session_token')
```

Use the `X-DreamFactory-Session-Token` header for all subsequent requests.

### 2. Connect Your Database

```bash
curl -X POST http://localhost:8088/api/v2/system/service \
  -H "Content-Type: application/json" \
  -H "X-DreamFactory-Session-Token: $TOKEN" \
  -d '{
    "name": "mydb",
    "label": "My Database",
    "type": "pgsql",
    "config": {
      "host": "your-db-host",
      "port": 5432,
      "database": "your_database",
      "username": "your_user",
      "password": "your_password"
    }
  }'
```

That's it — every table in your database now has a REST API.

### 3. Use Your APIs

```bash
# List all tables
curl http://localhost:8088/api/v2/mydb/_table \
  -H "X-DreamFactory-Session-Token: $TOKEN"

# Get records from a table
curl http://localhost:8088/api/v2/mydb/_table/users \
  -H "X-DreamFactory-Session-Token: $TOKEN"

# Filter records
curl "http://localhost:8088/api/v2/mydb/_table/users?filter=age%3E30&limit=10" \
  -H "X-DreamFactory-Session-Token: $TOKEN"

# Create a record
curl -X POST http://localhost:8088/api/v2/mydb/_table/users \
  -H "Content-Type: application/json" \
  -H "X-DreamFactory-Session-Token: $TOKEN" \
  -d '{"resource": [{"name": "Jane", "email": "jane@example.com"}]}'

# Update a record
curl -X PATCH http://localhost:8088/api/v2/mydb/_table/users/1 \
  -H "Content-Type: application/json" \
  -H "X-DreamFactory-Session-Token: $TOKEN" \
  -d '{"name": "Jane Updated"}'

# Delete a record
curl -X DELETE http://localhost:8088/api/v2/mydb/_table/users/1 \
  -H "X-DreamFactory-Session-Token: $TOKEN"
```

### 4. Create an API Key (for app access without admin session)

```bash
# Create a role
ROLE_ID=$(curl -s -X POST http://localhost:8088/api/v2/system/role \
  -H "Content-Type: application/json" \
  -H "X-DreamFactory-Session-Token: $TOKEN" \
  -d '{"name": "mydb-reader", "is_active": true}' \
  | jq -r '.id')

# Create an app with an API key
curl -X POST http://localhost:8088/api/v2/system/app \
  -H "Content-Type: application/json" \
  -H "X-DreamFactory-Session-Token: $TOKEN" \
  -d "{
    \"name\": \"my-app\",
    \"api_key\": \"$(openssl rand -hex 32)\",
    \"role_id\": $ROLE_ID,
    \"is_active\": true
  }"
```

Then use `X-DreamFactory-API-Key: <key>` header instead of session tokens.

### 5. View API Docs

Swagger/OpenAPI spec is at `http://localhost:8088/api/v2/api_docs`.

### Service Types

| Database | `type` value |
|----------|-------------|
| PostgreSQL | `pgsql` |
| MySQL / MariaDB | `mysql` |
| SQL Server | `sqlsrv` |
| SQLite | `sqlite` |
| Remote Web Service | `rws` |
| SOAP | `soap` |

## Configuration

All via environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `ADMIN_EMAIL` | `admin@dreamfactory.com` | Admin login email |
| `ADMIN_PASSWORD` | *(required)* | Admin password |
| `APP_DEBUG` | `false` | Debug mode |
| `APP_LOG_LEVEL` | `warning` | Log verbosity |
| `APP_KEY` | *(auto-generated)* | Laravel app key |
| `CORS_ORIGIN` | `*` | Allowed CORS origin |

## Resource Usage

| | DF Mini | Full DF Docker |
|---|---|---|
| **Image** | ~410 MB | ~2.6 GB |
| **RAM** | ~50 MB | ~190 MB |
| **Startup** | ~4 seconds | ~60 seconds |
| **Containers** | 1 | 5 |

## Upgrade Path

Outgrown Mini? Full DreamFactory adds MongoDB, 30+ database connectors, enterprise SSO (SAML, LDAP, OAuth), server-side scripting, scheduled tasks, and more.

## LLM / AI Integration

This repo includes an [`llms.txt`](llms.txt) file — a structured API reference designed for LLMs and AI coding assistants. It contains exact endpoint patterns, request/response shapes, code examples in Python/JavaScript/curl, and common gotchas. Feed it to your LLM to generate correct DF Mini integration code on the first try.

## License

Apache-2.0 — see [LICENSE](LICENSE) for details.
