ARG MYSQL_BASE_IMAGE=mysql:8.0
FROM ${MYSQL_BASE_IMAGE}

ENV MYSQL_SSL_CERT_DIR=/etc/mysql/certs

# Copy the FIPS-compliant config file and TLS material
COPY mysql/my.cnf /etc/mysql/conf.d/fips.cnf
COPY mysql/certs/ ${MYSQL_SSL_CERT_DIR}/

RUN chown -R mysql:mysql /etc/mysql/conf.d ${MYSQL_SSL_CERT_DIR} \
    && chmod 600 ${MYSQL_SSL_CERT_DIR}/server-key.pem \
    && chmod 644 ${MYSQL_SSL_CERT_DIR}/server-cert.pem ${MYSQL_SSL_CERT_DIR}/ca.pem
