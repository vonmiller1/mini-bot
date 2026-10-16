# DreamFactory Mini

**Turn SQL databases and web services into REST APIs.**

DreamFactory Mini is a slim, single-container edition of DreamFactory. Connect a database or web service and use the generated REST endpoints to work with its resources. There is no administration UI; setup and configuration are performed through the system API.

## Features

- SQL connectors for PostgreSQL, MySQL/MariaDB, SQL Server, and SQLite
- Remote Web Services (RWS) and SOAP connectors
- Generated REST endpoints and Swagger/OpenAPI documentation
- Session-token and API-key authentication
- SQLite-backed system database and file-based cache
- Docker Compose deployment with persistent application storage

Mini intentionally omits features available in the [full DreamFactory platform](https://github.com/dreamfactorysoftware/dreamfactory), including the administration UI, MongoDB, enterprise identity integrations, scripting, scheduled tasks, and email.

## Requirements

- Docker Engine with the Docker Compose plugin
- A reachable database to expose (optional when using SQLite as the data source)

## Quick start

Set credentials in your shell, then build and start the container:

```bash
export ADMIN_EMAIL='admin@example.com'
export ADMIN_PASSWORD='replace-with-a-unique-password-of-at-least-16-characters'
docker compose up -d --build
```

The API is available at `http://localhost:8088/api/v2`. On first start, the container initializes its system database and creates the administrator account. Check startup output with:

```bash
docker compose logs -f df-mini
```

The Compose file requires both `ADMIN_EMAIL` and `ADMIN_PASSWORD`. Choose a unique, strong password and do not commit credentials to source control.

## Connect a database

Log in to obtain a session token. The following Bash example requires `curl` and `jq`:

```bash
BASE_URL='http://localhost:8088/api/v2'

TOKEN=$(
  curl --fail --silent --show-error \
    -X POST "$BASE_URL/system/admin/session" \
    -H 'Content-Type: application/x-www-form-urlencoded' \
    --data-urlencode "email=$ADMIN_EMAIL" \
    --data-urlencode "password=$ADMIN_PASSWORD" |
    jq -r '.session_token'
)
```

Create a service for a PostgreSQL database:

```bash
curl --fail --silent --show-error \
  -X POST "$BASE_URL/system/service" \
  -H 'Content-Type: application/json' \
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
      "password": "your_database_password"
    }
  }'
```

Replace the example connection details with values for your database. Once the service is created, tables are available under `/{service-name}/_table`.

## Use the generated API

List tables and read records using the session token:

```bash
curl --fail --silent --show-error "$BASE_URL/mydb/_table" \
  -H "X-DreamFactory-Session-Token: $TOKEN"

curl --fail --silent --show-error "$BASE_URL/mydb/_table/users?limit=10" \
  -H "X-DreamFactory-Session-Token: $TOKEN"
```

Create a record (bulk table operations use a `resource` array):

```bash
curl --fail --silent --show-error \
  -X POST "$BASE_URL/mydb/_table/users" \
  -H 'Content-Type: application/json' \
  -H "X-DreamFactory-Session-Token: $TOKEN" \
  -d '{"resource":[{"name":"Jane","email":"jane@example.com"}]}'
```

Table endpoints support the standard REST operations for reading, creating, updating, and deleting records. Use an API key instead of a session token for application access: create an app through the system API and assign it a role scoped to the services, tables, and operations the client needs. Send the key in the `X-DreamFactory-API-Key` header.

## Supported service types

| Service | Type |
| --- | --- |
| PostgreSQL | `pgsql` |
| MySQL or MariaDB | `mysql` |
| Microsoft SQL Server | `sqlsrv` |
| SQLite | `sqlite` |
| Remote Web Service | `rws` |
| SOAP | `soap` |

## API documentation

The Swagger/OpenAPI endpoint is available at `http://localhost:8088/api/v2/api_docs`. The repository's [`llms.txt`](llms.txt) provides a structured reference for integrating DreamFactory Mini with AI coding tools.

## Configuration and storage

The supplied Compose configuration requires these variables:

| Variable | Required | Purpose |
| --- | --- | --- |
| `ADMIN_EMAIL` | Yes | Email for the initial administrator account |
| `ADMIN_PASSWORD` | Yes | Password for the initial administrator account |

Compose configures SQLite for DreamFactory's system database, disables debug mode, sets the log level to `warning`, and streams application logs to the container output. The named `df-mini-storage` volume persists application storage across container restarts and `docker compose down`.

Stop the container with `docker compose down`. This preserves the volume. **Do not use `docker compose down -v` unless you intend to delete the persisted application data.**

## Security notes

- The Compose port mapping publishes the API on port `8088` on the host. Restrict network access; do not expose an unprotected instance directly to the public internet.
- Use a unique administrator password and database credentials with only the permissions the API requires.
- Give API-key clients narrowly scoped roles. Avoid using the administrator session token in application code.
- For internet-facing deployments, put the service behind a properly configured TLS-terminating reverse proxy and manage secrets outside the repository.

## Upgrade path

If you need the administration UI, additional connectors, enterprise authentication, scripting, or scheduled tasks, consider the [full DreamFactory platform](https://github.com/dreamfactorysoftware/dreamfactory).

## License

DreamFactory Mini is distributed under the Apache-2.0 license. See [`LICENSE`](LICENSE) for details.
