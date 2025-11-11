#!/bin/sh

: "${LIFERAY_HOME:=/opt/liferay}"
: "${TOMCAT_KEYSTORE_PASSWORD:=changeit}"
: "${FIPS_TRUSTSTORE_PASSWORD:=changeit}"
: "${JNDI_KEYSTORE_PASSWORD:=changeit}"
: "${JNDI_DB_PASSWORD_ALIAS:=jdbc_liferay_password}"
: "${JNDI_DB_USERNAME:=root}"

KEYSTORE_PATH="${LIFERAY_HOME}/tomcat/conf/keystore.bcfks"
TRUSTSTORE_PATH="${LIFERAY_HOME}/tomcat/conf/fips-truststore.bcfks"
JNDI_KEYSTORE_PATH="${LIFERAY_HOME}/tomcat/conf/jndi-keystore.bcfks"
FIPS_KEY_PATH="${LIFERAY_HOME}/data/fips.key"

require_file() {
    if [ ! -f "$2" ]; then
        echo "### WARNING: Missing $1 at $2" >&2
    fi
}

require_file "Tomcat TLS keystore" "${KEYSTORE_PATH}"
require_file "FIPS truststore" "${TRUSTSTORE_PATH}"
require_file "JNDI credential keystore" "${JNDI_KEYSTORE_PATH}"
require_file "FIPS encryption key" "${FIPS_KEY_PATH}"

BASE_JVM_OPTS="--add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.lang.invoke=ALL-UNNAMED --add-exports=java.base/sun.security.provider=ALL-UNNAMED"

CATALINA_OPTS="${CATALINA_OPTS} ${BASE_JVM_OPTS} \
 -Djndi.keystore.password=${JNDI_KEYSTORE_PASSWORD} \
 -Djndi.db.alias=${JNDI_DB_PASSWORD_ALIAS} \
 -Djndi.db.username=${JNDI_DB_USERNAME} \
 -Dfips.truststore.password=${FIPS_TRUSTSTORE_PASSWORD} \
 -Dtomcat.keystore.password=${TOMCAT_KEYSTORE_PASSWORD} \
 -Djavax.net.ssl.keyStore=${KEYSTORE_PATH} \
 -Djavax.net.ssl.keyStorePassword=${TOMCAT_KEYSTORE_PASSWORD} \
 -Djavax.net.ssl.keyStoreType=BCFKS \
 -Djavax.net.ssl.trustStore=${TRUSTSTORE_PATH} \
 -Djavax.net.ssl.trustStorePassword=${FIPS_TRUSTSTORE_PASSWORD} \
 -Djavax.net.ssl.trustStoreType=BCFKS"

BC_PROVIDER_DIR="${LIFERAY_HOME}/tomcat/lib"
BC_PROVIDER_JARS=$(find "${BC_PROVIDER_DIR}" -maxdepth 1 -type f -name 'bc*-fips-*.jar' -print 2>/dev/null | tr '\n' ':' | sed 's/:$//')

if [ -n "${BC_PROVIDER_JARS}" ]; then
    CLASSPATH="${BC_PROVIDER_JARS}:${CLASSPATH}"
    CATALINA_OPTS="${CATALINA_OPTS} -Xbootclasspath/a:${BC_PROVIDER_JARS}"
else
    echo "### WARNING: No Bouncy Castle FIPS jars found under ${BC_PROVIDER_DIR}" >&2
fi

if [ "${FIPS_MODE:-false}" = "true" ]; then
    echo "### FIPS MODE ENABLED ###"
    CATALINA_OPTS="${CATALINA_OPTS} \
        -Djava.security.properties==${LIFERAY_HOME}/java.security \
        -Dorg.bouncycastle.fips.approved_only=true \
        -Djava.security.egd=file:/dev/./urandom"
else
    echo "### FIPS MODE DISABLED ###"
fi

export CATALINA_OPTS
