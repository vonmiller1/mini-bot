# mini-bot (DreamFactory Mini)

**Single-container REST API layer for SQL databases and web services—configured entirely through the HTTP API.**

## Overview

This repository packages **DreamFactory Mini**: a slim Docker deployment that connects PostgreSQL, MySQL/MariaDB, SQL Server, SQLite, remote web services, or SOAP endpoints and exposes generated REST resources with Swagger/OpenAPI documentation. There is no administration UI; provisioning uses the system API after the container starts. The stack is PHP 8.3, Laravel 11, Nginx, and PHP-FPM, with a SQLite-backed system database and file cache inside the container.

## Features

- SQL connectors for PostgreSQL, MySQL/MariaDB, SQL Server, and SQLite
- Remote Web Services (RWS) and SOAP connectors
- Generated REST endpoints and Swagger/OpenAPI documentation
- Session-token and API-key authentication
- SQLite-backed system database and file-based cache
- Docker Compose deployment with persistent application storage

Mini intentionally omits features available in the [full DreamFactory platform](https://github.com/dreamfactorysoftware/dreamfactory), including the administration UI, MongoDB, enterprise identity integrations, scripting, scheduled tasks, and email.

## Tech stack

| Layer | Technology |
| --- | --- |
| Runtime | PHP 8.3 (FPM), Nginx |
| Application | Laravel 11, DreamFactory packages (`df-core`, `df-system`, connectors) |
| System DB | SQLite (in-container) |
| Packaging | Docker multi-stage build, Docker Compose |
| API docs | Swagger/OpenAPI at `/api/v2/api_docs` |

## Prerequisites

- Docker Engine with the Docker Compose plugin (v2)
- A reachable database to expose (optional when using SQLite as the data source)
- `curl` and `jq` for the setup examples below (host shell only)

## Getting started

Clone the repository and set administrator credentials in your shell (do not commit secrets):

```bash
git clone https://github.com/vonmiller1/mini-bot.git
cd mini-bot
export ADMIN_EMAIL='admin@example.com'
export ADMIN_PASSWORD='replace-with-a-unique-password-of-at-least-16-characters'
docker compose up -d --build
```

## Running locally

The API listens on **port 8088** on the host:

- Base URL: `http://localhost:8088/api/v2`
- OpenAPI: `http://localhost:8088/api/v2/api_docs`

On first start, the entrypoint initializes the system database and creates the administrator account. Follow startup logs:

```bash
docker compose logs -f df-mini
```

Compose requires both `ADMIN_EMAIL` and `ADMIN_PASSWORD` (minimum 16 characters for the password).

## Connect a database

Log in to obtain a session token:

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

Replace the example connection details with values for your database. Tables are available under `/{service-name}/_table`.

## Use the generated API

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

Use an API key for application clients: create an app via the system API, assign a scoped role, and send `X-DreamFactory-API-Key`.

## Supported service types

| Service | Type |
| --- | --- |
| PostgreSQL | `pgsql` |
| MySQL or MariaDB | `mysql` |
| Microsoft SQL Server | `sqlsrv` |
| SQLite | `sqlite` |
| Remote Web Service | `rws` |
| SOAP | `soap` |

## Testing

This repository does not ship application test suites. To validate a deployment manually, use the health-oriented system endpoints and the curl flows above after `docker compose up`. Run any upstream DreamFactory or Laravel tests only from a full development checkout of DreamFactory—not from this Mini image build context.

## Project structure

| Path | Purpose |
| --- | --- |
| `Dockerfile` | Multi-stage image: Composer install on `df-base-img`, slim Ubuntu runtime |
| `docker-compose.yml` | Single-service Compose stack and required env vars |
| `docker-entrypoint.sh` | First-boot setup, admin user, Nginx/FPM tuning |
| `dreamfactory.conf` | Nginx site for Laravel front controller |
| `composer.json` | Mini dependency set (MongoDB and unused connectors omitted) |
| `llms.txt` | Structured API reference for LLM-assisted integration |

## Configuration

| Variable | Required | Purpose |
| --- | --- | --- |
| `ADMIN_EMAIL` | Yes | Initial administrator email |
| `ADMIN_PASSWORD` | Yes | Initial administrator password (min 16 characters) |
| `SERVERNAME` | No | Nginx `server_name` (default `localhost`) |
| `APP_LOG_LEVEL` | No | Log verbosity (Compose sets `warning`) |
| `LOG_TO_STDOUT` | No | Stream app log file to container stdout |
| `APP_KEY` | No | Laravel app key; generated on first boot if unset |
| `CORS_ORIGIN` | No | Default CORS origin when seeding empty CORS config |

Persistent data lives in the `df-mini-storage` Docker volume mounted at `/opt/dreamfactory/storage`.

Stop with `docker compose down` (volume retained). Avoid `docker compose down -v` unless you intend to wipe persisted data.

## Deployment

Build and run with Compose on any Docker host. For production, terminate TLS at a reverse proxy, restrict host firewall rules on port 8088, use strong unique credentials, and scope API keys to least privilege. The image exposes HTTP on port 80 inside the container (mapped to 8088 in the default Compose file).

## API documentation

OpenAPI: `http://localhost:8088/api/v2/api_docs`. See [`llms.txt`](llms.txt) for LLM-oriented endpoint documentation.

## Security notes

- Do not expose an unauthenticated instance directly to the public internet.
- Use unique administrator and database credentials with minimal privileges.
- Prefer API keys with narrow roles over long-lived admin session tokens in application code.
- Manage secrets via environment variables or a secrets manager—not committed files.

## Contributing

1. Fork the repository and create a feature branch from `main`.
2. Keep commits focused (one logical change per commit).
3. Open a pull request with a clear description of behavior and security impact.
4. Do not commit `.env` files, credentials, or production secrets.

## Upgrade path

For an administration UI, additional connectors, enterprise authentication, scripting, or scheduled tasks, use the [full DreamFactory platform](https://github.com/dreamfactorysoftware/dreamfactory).

## License

Apache-2.0. See [`LICENSE`](LICENSE).
