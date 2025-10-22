## 🛡️ Liferay DXP FIPS 140-3 Compliant Stack (MySQL, Elasticsearch)

This project provides a development environment for running Liferay DXP with FIPS 140-3 compliant backend services:

  * **Liferay DXP:** Runs on a custom image based on the provided `Dockerfile`.
  * **Database:** Uses a FIPS-enabled **MySQL** image (`[docker-hardened-enterprise-account]/dhi-mysql:8.0.43-fips`).
  * **Search:** Uses an **Elasticsearch** image configured for FIPS 140-3 compliance.

-----

## 📂 Project Structure

The repository has the following file structure:

```
.
├── docker-compose.yaml             # Defines the services (Liferay, Database, Search) and their configuration.
├── elasticsearch
│   ├── Dockerfile                  # Dockerfile to build the FIPS-ready Elasticsearch image.
│   └── elasticsearch.yml           # Configuration to enable FIPS mode for Elasticsearch.
├── liferay
│   ├── bundle                      # Parend folder for the Liferay DXP distribution zip file.
│   ├── configs
│   │   ├── bouncycastle            # FIPS-compliant Bouncy Castle security provider jars.
│   │   ├── jdbc-driver             # MySQL JDBC driver.
│   │   ├── jdk                     # Custom java.security file for FIPS setup.
│   │   ├── osgi                    # OSGi configurations for Liferay, including Elasticsearch connection.
│   │   ├── portal
│   │   │   └── portal-ext.properties # Liferay's portal-ext.properties.
│   │   └── tomcat                  # Tomcat's jvm.options (setenv.sh configuration in Dockerfile).
│   └── Dockerfile                  # Dockerfile to build the Liferay DXP image.
└── README.md                       # This file.
```

-----

## 🛠️ Prerequisites

  * **Docker:** Installed and running on your system.
  * **Docker Compose:** Installed (or use the `docker compose` command if using newer Docker versions).
  * **Liferay DXP Bundle:** The Liferay DXP ZIP file must be placed in `liferay/bundle/`.

-----

## 🚀 Getting Started

### 1\. Build and Run the Stack

Execute the following command from the root directory to build the custom images and start the services:

```bash
docker compose up --build -d
```

  * The **Liferay DXP** image will be built using `liferay/Dockerfile`. This process installs the necessary dependencies, sets up the Liferay user, unzips the bundle, and copies custom configuration files (`portal-ext.properties`, etc.) into the image.
  * The **Elasticsearch** image will be built using `elasticsearch/Dockerfile` and configured via `elasticsearch/elasticsearch.yml` to enable FIPS mode: `xpack.security.fips_mode.enabled: true`.

### 2\. Access the Applications

Once all services are up and running:

| Service | Port | Host | Configuration Notes |
| :--- | :--- | :--- | :--- |
| **Liferay DXP** | `8081` | `http://localhost:8081` | Exposed for HTTP access. |
| **Database (MySQL)** | `3307` | `localhost:3307` | Exposed for development access. Uses `lportal` database and `root` password. |
| **Elasticsearch** | *Internal* | *N/A* | Not exposed externally. Liferay connects internally via the Docker network. |

### 3\. Check Logs

You can check the logs for any service to monitor the startup process:

```bash
# Check Liferay logs
docker compose logs -f liferay

# Check Database logs
docker compose logs -f database

# Check Search logs
docker compose logs -f search
```

### 4\. Stop and Clean Up

To stop and remove all running containers, networks, and volumes defined in the `docker-compose.yaml`:

```bash
docker compose down -v
```

The `-v` flag ensures that the defined **volumes** (`elastic-data` and `mysql-fips-data`) are also removed, useful for a clean slate.

-----

### 5\. Access

Access http://localhost:8080/ and login with [USER] and [PASSWORD]