## 🛡️ Liferay DXP FIPS 140‑3 Reference Stack

This repository assembles a Docker-based environment that keeps **Liferay DXP**, **MySQL**, and **Elasticsearch** inside a FIPS 140‑3 perimeter. Every image is intentionally bare-bones: they only copy what you place under `configs/` or `certs/`, so you keep full control over keys, ciphers, and provider versions.

| Service | Image | Highlights |
| :-- | :-- | :-- |
| `database` | `liferay-fips/mysql:8.0.43-fips` | Hardened `mysql:8.0.43`, TLS-only, `ssl_fips_mode=STRICT`, user-supplied cert chain. |
| `liferay` | `liferay-fips/dxp:latest` | Temurin 21 + Bouncy Castle FIPS JSSE. Loads your keystore, truststore, and AES secrets. |
| `search` | `liferay-fips/elasticsearch:8.17.2-fips` | Runs Elastic 8 in FIPS mode (requires Platinum/trial license) with your CA + node certs. |

---

## Repository layout

```
.
├── docker-compose.yaml
├── elasticsearch/
│   ├── certs/        # elastic-ca.crt, elastic-node.crt, elastic-node.key
│   ├── config/
│   │   └── elasticsearch.yml
│   └── Dockerfile
├── liferay/
│   ├── bundle/       # Liferay DXP bundle (.zip/.tar.gz) + activation key
│   ├── configs/
│   │   ├── bouncycastle/     # bc-fips, bcpkix-fips, bctls-fips, bcutil-fips jars
│   │   ├── jdbc-driver/      # MySQL Connector/J
│   │   ├── jdk/java.security # overrides SunJSSE with BC JSSE
│   │   ├── osgi/configs/     # Remote Elasticsearch config
│   │   ├── portal/           # portal-ext.properties + fips.key
│   │   └── tomcat/
│   │        ├── security/           # keystore.bcfks (HTTPS) + fips-truststore.bcfks
│   │        ├── support/            # TomcatUrlHandlerDisabler agent sources
│   │        ├── root/               # Optional JSPs (e.g., fips_verify.jsp)
│   │        ├── context.xml         # TLS-enabled MySQL datasource
│   │        ├── server.xml          # HTTPS connector bound to BCFKS keystore
│   │        ├── setenv.sh           # Injects BC FIPS jars + JVM options
│   │        └── run-java-wrapper.sh # Normalizes -Djava.protocol.handler.pkgs before catalina.sh runs
│   └── Dockerfile
├── security-ext/           # Ext module with patched SecureRandomUtil + build.gradle
├── tools/                   # Utility scripts (e.g., keystore helpers, TLS inspectors)
└── mysql/
    ├── certs/         # MySQL CA/server cert/key
    ├── initdb.d/      # SQL init scripts (creates liferay user with SSL)
    ├── my.cnf
    └── Dockerfile
```

---

## Required artifacts

### MySQL (`mysql/certs/`)

Drop `ca.pem`, `server-cert.pem`, and `server-key.pem`. See `mysql/certs/README.md` for sample OpenSSL commands. `mysql/my.cnf` already loads them and enforces TLS 1.2/1.3 with FIPS-friendly cipher suites.

<details>
<summary>Sample OpenSSL flow</summary>

```bash
cd mysql/certs
openssl genrsa -out ca-key.pem 4096
openssl req -x509 -new -key ca-key.pem -sha384 -days 3650 -out ca.pem -subj "/CN=mysql-ca"
openssl genrsa -out server-key.pem 4096
openssl req -new -key server-key.pem -out server.csr -subj "/CN=database" \
  -addext "subjectAltName=DNS:database,IP:127.0.0.1"
openssl x509 -req -in server.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial \
  -out server-cert.pem -days 825 -sha384 -extensions san \
  -extfile <(printf "[san]\nsubjectAltName=DNS:database,IP:127.0.0.1")
chmod 600 server-key.pem
rm -f ca-key.pem server.csr
```

</details>

### Liferay / Tomcat (`liferay/configs/`)

| File | Purpose |
| :-- | :-- |
| `portal/fips.key` | 32-byte AES key for `passwords.encryption.key.provider=file`. |
| `tomcat/security/keystore.bcfks` | HTTPS certificate for 8443. Store type **must** be BCFKS. |
| `tomcat/security/fips-truststore.bcfks` | Trusts MySQL + Elasticsearch CAs. Also BCFKS. |
| `tomcat/server.xml` | HTTPS connector already wired for the keystore/truststore paths. |
| `tomcat/context.xml` | JNDI datasource with TLS-only MySQL URL and keystore-based password injection. |
| `bouncycastle/*.jar` | `bc-fips`, `bcutil-fips`, `bcpkix-fips`, `bctls-fips` jars from the **same** BC FIPS release. |

> **BC FIPS tooling:** Oracle `keytool` needs both `bc-fips` and `bcutil-fips` on `-providerpath`. Example:
>
> ```bash
> BC_FIPS_JAR=bc-fips-2.1.2.jar
> BC_UTIL_JAR=bcutil-fips-2.1.5.jar
> PROVIDERS="liferay/configs/bouncycastle/${BC_FIPS_JAR}:liferay/configs/bouncycastle/${BC_UTIL_JAR}"
> keytool -genkeypair ... \
>   -storetype BCFKS \
>   -providerclass org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider \
>   -providerpath "${PROVIDERS}"
> ```

<details>
<summary>Generate HTTPS keystore + truststore</summary>

```bash
BC_FIPS_JAR=bc-fips-2.1.2.jar
BC_UTIL_JAR=bcutil-fips-2.1.5.jar
PROVIDERS="liferay/configs/bouncycastle/${BC_FIPS_JAR}:liferay/configs/bouncycastle/${BC_UTIL_JAR}"

keytool -genkeypair \
  -alias liferay-https \
  -dname "CN=liferay,OU=DXP,O=Example,L=Remote,ST=Remote,C=US" \
  -keyalg RSA -keysize 3072 -validity 3650 \
  -storepass "$TOMCAT_KEYSTORE_PASSWORD" \
  -keypass "$TOMCAT_KEYSTORE_PASSWORD" \
  -keystore liferay/configs/tomcat/security/keystore.bcfks \
  -storetype BCFKS \
  -providerclass org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider \
  -providerpath "${PROVIDERS}"

for CA in mysql/certs/ca.pem elasticsearch/certs/elastic-ca.crt; do
  keytool -importcert -noprompt \
    -alias "$(basename "$CA")" \
    -file "$CA" \
    -storepass "$FIPS_TRUSTSTORE_PASSWORD" \
    -keystore liferay/configs/tomcat/security/fips-truststore.bcfks \
    -storetype BCFKS \
    -providerclass org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider \
    -providerpath "${PROVIDERS}"
done
```

</details>

### Elasticsearch (`elasticsearch/certs/`)

Provide `elastic-ca.crt`, `elastic-node.crt`, `elastic-node.key`. The CA must also be imported into Liferay’s truststore. Because Elastic requires Platinum (or trial) licensing for FIPS mode, run:

```bash
curl -k -u elastic:elasticFips!2024 \
  -XPOST https://search:9200/_license/start_trial?acknowledge=true
```

before you re-enable `xpack.security.fips_mode`.

<details>
<summary>Sample node certificate</summary>

```bash
cd elasticsearch/certs
openssl genrsa -out elastic-ca.key 4096
openssl req -x509 -new -key elastic-ca.key -sha384 -days 3650 \
  -out elastic-ca.crt -subj "/CN=elastic-ca"
openssl genrsa -out elastic-node.key 4096
openssl req -new -key elastic-node.key -out elastic-node.csr -subj "/CN=search" \
  -addext "subjectAltName=DNS:search,IP:127.0.0.1"
openssl x509 -req -in elastic-node.csr -CA elastic-ca.crt -CAkey elastic-ca.key -CAcreateserial \
  -out elastic-node.crt -days 825 -sha384 -extensions san \
  -extfile <(printf "[san]\nsubjectAltName=DNS:search,IP:127.0.0.1")
chmod 600 elastic-node.key
rm -f elastic-ca.key elastic-node.csr
```

</details>

---

## Helper components

To keep the stack stable under FIPS+BC JSSE, we ship a few custom utilities:

| Helper | File | Why it exists |
| :-- | :-- | :-- |
| **Protocol normalizer** | `liferay/configs/tomcat/run-java-wrapper.sh` | Tomcat’s scripts and Liferay both append `-Djava.protocol.handler.pkgs`. The wrapper deduplicates/merges them before invoking `java`. |
| **URL handler agent** | `liferay/configs/tomcat/support/TomcatUrlHandlerDisabler.java` + `MANIFEST.MF` | Equinox also registers a `URLStreamHandlerFactory`. The agent clears Tomcat’s factory just before Equinox loads so we avoid `java.lang.Error: factory already defined`. |
| **Trust manager override** | `liferay/configs/jdk/java.security` | Forces BC JSSE to provide the default KeyManager/TrustManager factories. This sidesteps JDK 21’s call into `ExtendedSSLSession.getStatusResponses()` that the BC classes don’t implement. |
| **BC keystore helper** | `tools/ImportPassword.java` | Tiny CLI utility that inserts plaintext secrets (e.g., DB passwords) into a BCFKS keystore using the BC FIPS provider. Use this if you prefer not to keep cleartext passwords in `setenv.sh`. |

These helpers are copied and built as part of the Liferay Dockerfile; you don’t need to run anything manually.

<details>
<summary>Using <code>ImportPassword</code></summary>

```bash
cd tools
javac -cp ../liferay/configs/bouncycastle/bc-fips-2.1.2.jar tools/ImportPassword.java
java -cp .:../liferay/configs/bouncycastle/bc-fips-2.1.2.jar \
     tools.ImportPassword \
     /path/to/keystore.bcfks keystorePass alias entryPass "MyPassword!"
```

This writes a secret entry into an existing BCFKS keystore—handy if you want to remove `JNDI_DB_PASSWORD` from the environment and reference the keystore instead.

</details>

---

## Patching `SecureRandomUtil` for BC FIPS (ext plugin)

Liferay’s stock `SecureRandomUtil` requests more than 262,144 bits from the BC FIPS DRBG and triggers `Number of bits per request limited to 262144`. The `security-ext` module ships a patched version that chunks requests to BC’s limit.

1) Ensure `security-ext/build.gradle` uses the same portal API version as your bundle (already set to `2025.q3.0` for this stack).
2) Extract the portal kernel from the DXP bundle once (needed for compileOnly):
   ```bash
   tar -xOf liferay/bundle/liferay-dxp-tomcat-2025.q3.0.tar.gz \
     liferay-dxp/tomcat/webapps/ROOT/WEB-INF/shielded-container-lib/portal-kernel.jar \
     > security-ext/lib/portal-kernel.jar
   ```
3) Build the ext WAR with Dockerized Gradle (no wrapper in repo). Use JDK 17 to match the portal classes; root avoids tmp/permission issues inside the container:
   ```bash
   docker run --rm -u root \
     -v "$PWD":/home/gradle/project \
     -w /home/gradle/project/security-ext \
     gradle:8-jdk17 gradle clean war
   ```
4) Bake the patched class into the image: the `liferay/Dockerfile` now overlays `SecureRandomUtil.class` into `portal-kernel.jar` if it exists at `security-ext/build/classes/java/main/com/liferay/portal/kernel/security/SecureRandomUtil.class`. Always rebuild the ext **before** building the Liferay image so the class is present.
5) Build and start Liferay:
   ```bash
   docker compose build liferay
   docker compose up -d liferay
   ```
6) Verify the patched class is present:
   ```bash
   docker compose exec liferay sh -c "jar tf /opt/liferay/tomcat/webapps/ROOT/WEB-INF/shielded-container-lib/portal-kernel.jar | grep SecureRandomUtil"
   ```
   If it shows up, the BC DRBG limit patch is in effect at bootstrap.

## Base image customization

The default Liferay base image is set to `yourorg/liferay-base:21.0-jdk-debian13` in both `liferay/Dockerfile` and `docker-compose.yaml`. Replace `yourorg` (and the tag) with your own registry/image name if you publish a customized base image.

## FIPS verification page

An optional JSP at `liferay/configs/tomcat/root/fips_verify.jsp` is copied into `tomcat/webapps/ROOT/`. After rebuilding and starting Liferay, open `https://<host>:8443/fips_verify.jsp` (or `http://<host>:8080/fips_verify.jsp` if HTTP is enabled) to confirm the BC FIPS provider is installed and in approved-only mode.

## Post-compose: create the database user

When starting from clean volumes, the MySQL image now seeds the `liferay` user (`liferay`/`liferay`) automatically via `mysql/initdb.d/01-create-liferay.sql` and enforces SSL. If you change `JNDI_DB_PASSWORD`, update that SQL accordingly and rebuild the MySQL image.

---

## Environment variables

| Variable | Default | Notes |
| :-- | :-- | :-- |
| `MYSQL_ROOT_PASSWORD` | `root` | Used by the container health check. |
| `FIPS_MODE` | `true` | Adds the BC `java.security` override + FIPS JVM flags. |
| `JNDI_DB_USERNAME` / `JNDI_DB_PASSWORD` | `liferay` / `liferay` | Passed to Tomcat as `-Djndi.db.*` and injected into `context.xml`. |
| `TOMCAT_KEYSTORE_PASSWORD` / `FIPS_TRUSTSTORE_PASSWORD` | `liferay` | Change to match your BCFKS files. |
| `ELASTIC_PASSWORD` | `elasticFips!2024` | Keep in sync with the OSGi config (`com.liferay.portal.search.elasticsearch7.configuration.ElasticsearchConfiguration.config`). |

Place them in `.env` or export them before running `docker compose`.

---

## Build & run

1. Copy the Liferay DXP bundle archive (and activation key) into `liferay/bundle/`.
2. Populate every artifact described above (keystores, truststores, certs, `fips.key`, BC jars).
3. Start the stack:

```bash
docker compose up --build
```

Liferay waits for the MySQL health check before booting. To tear everything down:

```bash
docker compose down -v
```

### Endpoints

| Component | URL / Host | Description |
| :-- | :-- | :-- |
| Liferay HTTP | `http://localhost:8081` | Default connector (behind Tomcat). |
| Liferay HTTPS | `https://localhost:8443` | Uses your BCFKS keystore. |
| MySQL | `localhost:3307` | TLS-only, connects with the `liferay` user/password. |
| Elasticsearch | `https://search:9200` (Compose network) | Requires the `elastic` basic-auth credentials. |

---

## Elasticsearch ↔ Liferay config

* `liferay/configs/osgi/configs/com.liferay.portal.search.elasticsearch7.configuration.ElasticsearchConfiguration.config`
  * `networkHostAddresses=["https://search:9200"]`
  * `httpSSLEnabled=true`, `truststoreType=BCFKS`, `truststorePath=/opt/liferay/tomcat/conf/fips-truststore.bcfks`
  * `username="elastic"`, `password="elasticFips!2024"`
* Update the truststore every time you rotate the Elastic CA.
* Ensure the Elastic container runs with `xpack.security.fips_mode.enabled=true` **and** a Platinum/trial license. Without that license Elastic refuses to start; with FIPS disabled the BC JSSE stack hits the missing `getStatusResponses()` call.

---

## Switching FIPS mode

The Liferay container honors `FIPS_MODE`:

```bash
FIPS_MODE=false docker compose up liferay
```

* `true` (default): uses `liferay/configs/jdk/java.security`, injects BC FIPS providers, and enables the extra TLS safeguards.
* `false`: launches Liferay with the stock Temurin security providers (useful for debugging non-FIPS regressions).

---

## Known follow-up work

This stack boots, connects to MySQL/Elasticsearch, and exposes HTTPS, but there are still application-level errors caused by the stricter BC FIPS providers (e.g., DRBG `Number of bits per request limited to 262144` in `SecureRandomUtil`). Those are intentionally **not** masked here—the objective is to give you a reproducible baseline where those issues can be addressed inside the Liferay codebase.

If you hit TLS issues again, verify:

1. All BC jars come from the same release.
2. The truststore contains both MySQL and Elasticsearch CAs.
3. Elasticsearch is running with a Platinum/trial license and `xpack.security.fips_mode.enabled=true`.
4. The BC helper jars are on the boot classpath (look for `-Xbootclasspath/a:/opt/liferay/tomcat/lib/bc-fips-...` in the JVM arguments).

## ✅ Verification Tips

* **Tomcat HTTPS**: `openssl s_client -connect localhost:8443 -tls1_3 -servername liferay`.
* **MySQL TLS**: `mysql --ssl-mode=VERIFY_CA --ssl-ca=mysql/certs/ca.pem -h 127.0.0.1 -P 3307 -u root -p`.
* **Elasticsearch TLS**: `curl --cacert elasticsearch/certs/elastic-ca.crt -u elastic:$ELASTIC_PASSWORD https://localhost:9200`.
* **Bouncy Castle FIPS**: Deploy the `fips_verify.jsp` snippet inside `tomcat/webapps/ROOT` and go to `https://<host>:8443/fips_verify.jsp` to confirm `FipsStatus.isReady()`.

---

## 📓 Notes & Next Steps

1. **Version control**: Do not commit actual keystores or secrets. Add them to your `.gitignore` or use a secure secret-management workflow.
2. **Health checks**: Add `healthcheck` sections in `docker-compose.yaml` if you want to gate dependent services.
3. **Production hardening**: Mount persistent volumes for `/var/lib/mysql`, `/usr/share/elasticsearch/data`, and `/opt/liferay/data` so you can preserve state between rebuilds.
4. **Certificate rotation**: When certificates or passwords change, rebuild the relevant images so the new material is baked in.

With these steps you get a portable, reproducible environment for validating Liferay DXP under FIPS 140-3 constraints while keeping full control over every cryptographic artifact.
