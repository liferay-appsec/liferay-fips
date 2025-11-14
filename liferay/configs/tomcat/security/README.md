Add the following BCFKS artifacts (all generated with the Bouncy Castle FIPS provider) before building the Liferay image:

1. `keystore.bcfks` – Holds the HTTPS certificate Tomcat presents on port 8443. The password must match `TOMCAT_KEYSTORE_PASSWORD`.
2. `fips-truststore.bcfks` – Trusts the MySQL and Elasticsearch certificate authorities so outbound TLS connections can be verified. Password must match `FIPS_TRUSTSTORE_PASSWORD`.

Keep these files out of version control. The README at the repository root contains sample `keytool` commands for generating them.
