#!/bin/sh

: "${LIFERAY_HOME:=/opt/liferay}"
: "${TOMCAT_KEYSTORE_PASSWORD:=changeit}"
: "${FIPS_TRUSTSTORE_PASSWORD:=changeit}"
: "${JNDI_DB_PASSWORD:=changeit}"
: "${JNDI_DB_USERNAME:=root}"

KEYSTORE_PATH="${LIFERAY_HOME}/tomcat/conf/keystore.bcfks"
TRUSTSTORE_PATH="${LIFERAY_HOME}/tomcat/conf/fips-truststore.bcfks"
FIPS_KEY_PATH="${LIFERAY_HOME}/data/fips.key"

require_file() {
    if [ ! -f "$2" ]; then
        echo "### WARNING: Missing $1 at $2" >&2
    fi
}

require_file "Tomcat TLS keystore" "${KEYSTORE_PATH}"
require_file "FIPS truststore" "${TRUSTSTORE_PATH}"
require_file "FIPS encryption key" "${FIPS_KEY_PATH}"

BC_PROVIDER_DIR="${LIFERAY_HOME}/tomcat/lib"
BC_PROVIDER_JARS=$(find "${BC_PROVIDER_DIR}" -maxdepth 1 -type f -name 'bc*-fips-*.jar' -print 2>/dev/null | tr '\n' ':' | sed 's/:$//')

if [ -n "${BC_PROVIDER_JARS}" ]; then
    CLASSPATH="${BC_PROVIDER_JARS}:${CLASSPATH}"
    CATALINA_OPTS="${CATALINA_OPTS} -Xbootclasspath/a:${BC_PROVIDER_JARS}"
else
    echo "### WARNING: No Bouncy Castle FIPS jars found under ${BC_PROVIDER_DIR}" >&2
fi

# Keep the Equinox URL handler factory from being re-registered during bootstrap.
BASE_JVM_OPTS="--add-opens=java.base/java.lang=ALL-UNNAMED --add-opens=java.base/java.lang.invoke=ALL-UNNAMED --add-opens=java.base/java.net=ALL-UNNAMED --add-exports=java.base/sun.security.provider=ALL-UNNAMED -Dosgi.framework.install.url.handlers=false"

CATALINA_OPTS="${CATALINA_OPTS} ${BASE_JVM_OPTS} \
 -Djndi.db.username=${JNDI_DB_USERNAME} \
 -Djndi.db.password=${JNDI_DB_PASSWORD} \
 -Dfips.truststore.password=${FIPS_TRUSTSTORE_PASSWORD} \
 -Dtomcat.keystore.password=${TOMCAT_KEYSTORE_PASSWORD} \
 -Djavax.net.ssl.trustStore=${TRUSTSTORE_PATH} \
 -Djavax.net.ssl.trustStorePassword=${FIPS_TRUSTSTORE_PASSWORD} \
 -Djavax.net.ssl.trustStoreType=BCFKS"

CATALINA_OPTS="${CATALINA_OPTS} -javaagent:${LIFERAY_HOME}/tomcat/lib/tomcat-url-handler-disabler.jar"

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

RUN_JAVA_WRAPPER="${LIFERAY_HOME}/tomcat/bin/run-java-wrapper.sh"
require_file "Tomcat JVM wrapper" "${RUN_JAVA_WRAPPER}"
if [ -x "${RUN_JAVA_WRAPPER}" ]; then
    _RUNJAVA="${RUN_JAVA_WRAPPER}"
fi
