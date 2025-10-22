# Liferay DXP Fips Compliant Env

Liferay DXP 7.4 running on docker compose.

## Requirements

* Docker and Docker Compose (CE edition) - version 24.0.2

## Start the environment

```
docker compose up --build -d
```

## Get logs:

```
docker compose logs -f liferay
```

## Access

Access http://localhost:8080/ and login with [USER] and [PASSWORD]