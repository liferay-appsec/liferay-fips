Place the following PEM-encoded assets in this directory before building the Elasticsearch image:

1. `elastic-ca.crt` – Certificate authority that signs every node certificate.
2. `elastic-node.crt` – Node certificate for the `search` container (CN/SAN should include `search` and `localhost`).
3. `elastic-node.key` – Private key for `elastic-node.crt`. Ensure permissions restrict access (`chmod 600`).

These files are mounted into `/usr/share/elasticsearch/config/certs/` by the Dockerfile and referenced by `elasticsearch/config/elasticsearch.yml`. Use your organization’s PKI or the sample `openssl` commands in the top-level README to recreate them.
