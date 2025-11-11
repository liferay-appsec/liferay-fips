## 🛡️ Liferay DXP FIPS 140-3 Reference Stack

This repository assembles a Docker-based environment that keeps **Liferay DXP**, **MySQL**, and **Elasticsearch** inside a FIPS 140-3 compliant perimeter. The images are purposely minimal: they only assemble what you provide. All TLS certificates, keystores, truststores, and encryption keys must be created **before** you build the containers.

| Service | Image | Highlights |
| :-- | :-- | :-- |
| `database` | `liferay-fips/mysql:8.0.43-fips` | Hardened `mysql:8.0.43` derivative, enforces TLS 1.2/1.3, strict cipher suites, and `ssl_fips_mode=STRICT`. |
| `liferay` | `liferay-fips/dxp:latest` | Eclipse Temurin 21 base, bundles Bouncy Castle FIPS jars, consumes user-provided keystores/FIPS keys, connects to MySQL + Elasticsearch through TLS. |
| `search` | `liferay-fips/elasticsearch:8.17.2-fips` | Elasticsearch 8.17 with `xpack.security.fips_mode.enabled`, requires user-supplied CA + node certificate. |

---

## 📂 Repository Layout

```
.
├── docker-compose.yaml
├── elasticsearch
│   ├── certs/               # Drop elastic-ca.crt, elastic-node.crt, elastic-node.key here.
│   ├── config/elasticsearch.yml
│   └── Dockerfile
├── liferay
│   ├── bundle/              # Liferay DXP bundle (.zip/.tar.gz) + activation key.
│   ├── configs
│   │   ├── bouncycastle/    # Bouncy Castle FIPS jars (already provided).
│   │   ├── jdbc-driver/     # MySQL Connector/J (already provided).
│   │   ├── jdk/java.security
│   │   ├── osgi/configs/    # Remote Elasticsearch configuration.
│   │   ├── portal/          # portal-ext.properties + FIPS AES key (user provided).
│   │   └── tomcat/          # context.xml, server.xml, setenv.sh, security README.
│   └── Dockerfile
└── mysql
    ├── certs/               # MySQL TLS CA/server cert/key (replace with your own).
    ├── my.cnf
    └── Dockerfile
```

---

## 🔑 Bring Your Own FIPS Assets

Only the bundle extraction is automated. Everything else must be created ahead of time and copied into the folders noted below. Replace the sample commands with your real subject names, passwords, and storage policies.

### 1. MySQL TLS Materials (`mysql/certs/`)

Required files: `ca.pem`, `server-cert.pem`, `server-key.pem`.

Example (OpenSSL):

```bash
cd mysql/certs
openssl genrsa -out ca-key.pem 4096
openssl req -x509 -new -key ca-key.pem -sha384 -days 3650 -out ca.pem -subj "/CN=mysql-ca"
openssl genrsa -out server-key.pem 4096
openssl req -new -key server-key.pem -out server.csr -subj "/CN=mysql"
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial \
  -out server-cert.pem -days 825 -sha384 -extfile <(printf "subjectAltName=DNS:database,IP:127.0.0.1")
chmod 600 server-key.pem
rm -f ca-key.pem server.csr
```

`mysql/my.cnf` already enables TLS 1.2/1.3, enforces FIPS cipher suites, and sets `ssl_fips_mode=STRICT`. Adjust the paths if you relocate the certs.

### 2. Liferay / Tomcat Security Assets

Place the following files before building the Liferay image:

| File | Path | Purpose | How to create |
| :-- | :-- | :-- | :-- |
| `keystore.bcfks` | `liferay/configs/tomcat/security/keystore.bcfks` | HTTPS certificate for Tomcat (port 8443). | Generate with Bouncy Castle FIPS provider (`keytool -genkeypair ... -storetype BCFKS`). Password must match `TOMCAT_KEYSTORE_PASSWORD`. |
| `fips-truststore.bcfks` | same folder | Trusts the MySQL and Elasticsearch CAs for outbound TLS. | Import each CA cert with `keytool -importcert ...`. Password must match `FIPS_TRUSTSTORE_PASSWORD`. |
| `jndi-keystore.bcfks` | same folder | Stores the database password referenced by the `KeyStoreCredentialHandler`. | `keytool -importpass -alias <JNDI_DB_PASSWORD_ALIAS>`; store password = `JNDI_KEYSTORE_PASSWORD`. |
| `fips.key` | `liferay/configs/portal/fips.key` | 32-byte base64 string used by `passwords.encryption.key.provider`. | `openssl rand -base64 32 > liferay/configs/portal/fips.key`. |
| `server.xml` | `liferay/configs/tomcat/server.xml` | Tomcat descriptor already wired for HTTPS + TLS truststore. Customize as needed. |

> **Bouncy Castle jars (required for both v1 and v2 lines):** place all of the following in `liferay/configs/bouncycastle/`: `bc-fips-*.jar`, `bcutil-fips-*.jar`, `bcpkix-fips-*.jar`, and `bctls-fips-*.jar`. All jars **must** come from the same Bouncy Castle FIPS release. Mixing v1 and v2 artifacts leads to missing-class errors (e.g., `org.bouncycastle.asn1.eac.EACObjectIdentifiers`) when Tomcat builds the JSSE context.

Sample keystore creation (requires Bouncy Castle FIPS jars already in `liferay/configs/bouncycastle`):

```bash
BC_JAR=bc-fips-1.0.2.6.jar
JAVA_HOME=/path/to/jdk

# HTTPS keystore
keytool -genkeypair \
  -alias liferay-https \
  -dname "CN=liferay, OU=DXP, O=Example, L=Remote, S=Remote, C=US" \
  -keyalg RSA -keysize 3072 -validity 3650 \
  -storepass "$TOMCAT_KEYSTORE_PASSWORD" \
  -keypass "$TOMCAT_KEYSTORE_PASSWORD" \
  -keystore liferay/configs/tomcat/security/keystore.bcfks \
  -storetype BCFKS \
  -providerclass org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider \
  -providerpath liferay/configs/bouncycastle/$BC_JAR

# Truststore (import MySQL + Elasticsearch CAs)
for CA in mysql/certs/ca.pem elasticsearch/certs/elastic-ca.crt; do
  keytool -importcert -noprompt \
    -alias "$(basename $CA)" \
    -file "$CA" \
    -storepass "$FIPS_TRUSTSTORE_PASSWORD" \
    -keystore liferay/configs/tomcat/security/fips-truststore.bcfks \
    -storetype BCFKS \
    -providerclass org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider \
    -providerpath liferay/configs/bouncycastle/$BC_JAR
done

# JNDI password keystore (use the helper tool)
javac -cp liferay/configs/bouncycastle/$BC_JAR -d tools/bin tools/ImportPassword.java

java -cp tools/bin:liferay/configs/bouncycastle/$BC_JAR \
  -Djava.security.properties=liferay/configs/jdk/java.security \
  tools.ImportPassword \
  liferay/configs/tomcat/security/jndi-keystore.bcfks \
  "$JNDI_KEYSTORE_PASSWORD" \
  "$JNDI_DB_PASSWORD_ALIAS" \
  "$JNDI_KEYSTORE_PASSWORD" \
  "$MYSQL_ROOT_PASSWORD"
```

### 3. Elasticsearch TLS Materials (`elasticsearch/certs/`)

Required files: `elastic-ca.crt`, `elastic-node.crt`, `elastic-node.key`. They are referenced by `elasticsearch/config/elasticsearch.yml` for both HTTP and transport layers.

Example:

```bash
cd elasticsearch/certs
openssl genrsa -out elastic-ca.key 4096
openssl req -x509 -new -key elastic-ca.key -sha384 -days 3650 -out elastic-ca.crt -subj "/CN=elastic-ca"
openssl genrsa -out elastic-node.key 4096
openssl req -new -key elastic-node.key -out elastic-node.csr -subj "/CN=search" \
  -addext "subjectAltName=DNS:search,IP:127.0.0.1"
openssl x509 -req -in elastic-node.csr -CA elastic-ca.crt -CAkey elastic-ca.key -CAcreateserial \
  -out elastic-node.crt -days 825 -sha384 -extensions san -extfile <(printf "[san]\nsubjectAltName=DNS:search,IP:127.0.0.1")
chmod 600 elastic-node.key
rm -f elastic-ca.key elastic-node.csr
```

Remember to import `elastic-ca.crt` into Liferay’s truststore (`fips-truststore.bcfks`).

---

## ⚙️ Environment Variables

| Variable | Default | Description |
| :-- | :-- | :-- |
| `MYSQL_ROOT_PASSWORD` | `root` | MySQL root password. Must match the password stored in `jndi-keystore.bcfks`. |
| `FIPS_MODE` | `true` | Toggles the Bouncy Castle FIPS provider overrides for Liferay. |
| `TOMCAT_KEYSTORE_PASSWORD` | `changeit` | Protects `keystore.bcfks`. |
| `FIPS_TRUSTSTORE_PASSWORD` | `changeit` | Protects `fips-truststore.bcfks`. |
| `JNDI_KEYSTORE_PASSWORD` | `changeit` | Protects `jndi-keystore.bcfks`. |
| `JNDI_DB_PASSWORD_ALIAS` | `jdbc_liferay_password` | Alias that stores the DB password inside `jndi-keystore.bcfks`. |
| `JNDI_DB_USERNAME` | `root` | Username injected into the Tomcat `Resource`. |
| `ELASTIC_PASSWORD` | `elasticFips!2024` | Password for the built-in `elastic` user (keep in sync with the OSGi config). |

Set them in your shell or via a `.env` file before running `docker compose`.

---

## 🚀 Build & Run

1. Populate every required asset described above.
2. Place the Liferay DXP bundle archive (and activation key) in `liferay/bundle/`.
3. Build and start:

```bash
docker compose up --build
```

After the containers start:

| Component | URL / Host | Notes |
| :-- | :-- | :-- |
| Liferay HTTP | http://localhost:8081 | Default connector. |
| Liferay HTTPS | https://localhost:8443 | Uses your `keystore.bcfks`. |
| MySQL | localhost:3307 | TLS-only. |
| Elasticsearch | https://search:9200 (inside network) | TLS + basic auth enabled. |

Shutdown and cleanup:

```bash
docker compose down -v
```

---

## 🔍 Elasticsearch + Liferay Integration

* `liferay/configs/osgi/configs/com.liferay.portal.search.elasticsearch7.configuration.ElasticsearchConfiguration.config` points to `https://search:9200`, enables TLS, and expects the truststore to contain `elastic-ca.crt`.
* Update `ELASTIC_PASSWORD` (compose) and the `.config` file together when rotating credentials.
* If you change the Elasticsearch hostname/certificates, regenerate the truststore and update the configuration accordingly.

---

## 🔁 Switching Between Normal and FIPS Mode

The Liferay container checks `FIPS_MODE` at runtime:

```bash
FIPS_MODE=false docker compose up liferay
```

Disabling FIPS skips the `java.security` override but still uses your keystore/truststore. Re-enable with `FIPS_MODE=true` for production parity.

---

## ✅ Verification Tips

* **Tomcat HTTPS**: `openssl s_client -connect localhost:8443 -tls1_3 -servername liferay`.
* **MySQL TLS**: `mysql --ssl-mode=VERIFY_CA --ssl-ca=mysql/certs/ca.pem -h 127.0.0.1 -P 3307 -u root -p`.
* **Elasticsearch TLS**: `curl --cacert elasticsearch/certs/elastic-ca.crt -u elastic:$ELASTIC_PASSWORD https://localhost:9200`.
* **Bouncy Castle FIPS**: Deploy the `fips_verify.jsp` snippet from the original guide inside `tomcat/webapps/ROOT` to confirm `FipsStatus.isReady()`.

---

## 📓 Notes & Next Steps

1. **Version control**: Do not commit actual keystores or secrets. Add them to your `.gitignore` or use a secure secret-management workflow.
2. **Health checks**: Add `healthcheck` sections in `docker-compose.yaml` if you want to gate dependent services.
3. **Production hardening**: Mount persistent volumes for `/var/lib/mysql`, `/usr/share/elasticsearch/data`, and `/opt/liferay/data` so you can preserve state between rebuilds.
4. **Certificate rotation**: When certificates or passwords change, rebuild the relevant images so the new material is baked in.

With these steps you get a portable, reproducible environment for validating Liferay DXP under FIPS 140-3 constraints while keeping full control over every cryptographic artifact.
