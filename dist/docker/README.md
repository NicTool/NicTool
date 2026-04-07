# Docker Development Environment

Everything you need to run NicTool locally and execute the test suite. The Docker Compose setup gives you a MariaDB instance and an Apache/mod_perl web container with the full NicTool stack.

## Getting Started

Generate a `.env` file with random passwords (only needed once):

```bash
bash dist/docker/generate-env.sh
```

Build and start the containers:

```bash
docker compose -f dist/docker/docker-compose.yml build web
docker compose -f dist/docker/docker-compose.yml up -d
```

The entrypoint should handle DB schema creation, test user setup, and WebAuthn config automatically on first boot. Wait for the web container health check to go green:

```bash
docker compose -f dist/docker/docker-compose.yml ps
```

Once `web` shows `healthy`, NicTool is running at http://localhost:8080.

## Logging In

The default admin account is username `root` with the password from `ROOT_USER_PASSWORD` in your `.env` file. To look it up:

```bash
grep ROOT_USER_PASSWORD dist/docker/.env
```

## Running Tests

Single test file (verbose output):

```bash
docker compose -f dist/docker/docker-compose.yml exec web bash -c \
  "cd /usr/local/nictool/server && prove -v t/05_webauthn.t"
```

Full server test suite:

```bash
docker compose -f dist/docker/docker-compose.yml exec web \
  make -C /usr/local/nictool/server test
```

## After Code Changes

The source is baked into the image at build time, so you need to rebuild after changing code:

```bash
docker compose -f dist/docker/docker-compose.yml build web
docker compose -f dist/docker/docker-compose.yml up -d
```

Since the db container has no persistent volume, tearing down and starting fresh gives you a clean slate:

```bash
docker compose -f dist/docker/docker-compose.yml down
docker compose -f dist/docker/docker-compose.yml up -d
```

## Upgrading an Existing Database

If you're reusing a db container from before a schema change (e.g., adding the WebAuthn tables in v2.44), you'll need to run the upgrade script. Pull the db password from your `.env` file:

```bash
docker compose -f dist/docker/docker-compose.yml exec web bash -c \
  "cd /usr/local/nictool/server/sql && echo '' | perl upgrade.pl \
   --dsn='DBI:mysql:database=nictool;host=db;port=3306' \
   --user=\$NICTOOL_DB_USER --pass=\$NICTOOL_DB_USER_PASSWORD"
```

The `--environment` vars are already set inside the container, so `$NICTOOL_DB_USER` and `$NICTOOL_DB_USER_PASSWORD` should just work (note the escaped `\$` so the shell expands them inside the container, not on your host).

## Paths Inside the Container

| What | Path |
|------|------|
| NicTool root | `/usr/local/nictool/` |
| Server tests | `/usr/local/nictool/server/t/` |
| Test config | `/usr/local/nictool/server/t/test.cfg` |
| Apache logs | `/var/log/apache2/` |
