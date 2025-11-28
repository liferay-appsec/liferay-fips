ARG LIFERAY_BASE_IMAGE=rafaelpraxedesliferayorg/dhi-eclipse-temurin:21.0-jdk-debian13-dev
FROM ${LIFERAY_BASE_IMAGE}

ENV LIFERAY_HOME=/opt/liferay \
    LIFERAY_USER=liferay \
    LIFERAY_GROUP=liferay \
    LIFERAY_UID=1001 \
    LIFERAY_GID=1001 \
    JAVA_HOME=/opt/java/openjdk/21

ARG TOMCAT_KEYSTORE_PASSWORD=changeit
ARG JNDI_DB_USERNAME=root

ENV TOMCAT_KEYSTORE_PASSWORD=${TOMCAT_KEYSTORE_PASSWORD} \
    JNDI_DB_USERNAME=${JNDI_DB_USERNAME}

RUN apt-get update && \
    apt-get install -y --no-install-recommends adduser ca-certificates gzip tar tree unzip && \
    rm -rf /var/lib/apt/lists/*

RUN groupadd -g ${LIFERAY_GID} ${LIFERAY_GROUP} && \
    useradd -u ${LIFERAY_UID} -g ${LIFERAY_GID} -m -d ${LIFERAY_HOME} -s /bin/bash ${LIFERAY_USER}

WORKDIR ${LIFERAY_HOME}

# Copy and extract the provided Liferay bundle (supports .zip and .tar.* archives)
COPY liferay/bundle /tmp/liferay-bundle
RUN set -eux; \
    mkdir -p "${LIFERAY_HOME}/deploy"; \
    ARCHIVE="$(find /tmp/liferay-bundle -maxdepth 1 -type f \( -name '*.tar.gz' -o -name '*.tgz' -o -name '*.zip' \) | head -n 1)"; \
    [ -n "${ARCHIVE}" ] || (echo "No Liferay bundle archive found under liferay/bundle" && exit 1); \
    TMP_EXTRACT="$(mktemp -d)"; \
    case "${ARCHIVE}" in \
        *.zip) unzip -q "${ARCHIVE}" -d "${TMP_EXTRACT}";; \
        *.tar.gz|*.tgz) tar -xzf "${ARCHIVE}" -C "${TMP_EXTRACT}";; \
        *) echo "Unsupported bundle format: ${ARCHIVE}" && exit 1;; \
    esac; \
    RELEASE_DIR="$(find "${TMP_EXTRACT}" -maxdepth 1 -type d -name 'liferay-*' -print -quit)"; \
    [ -n "${RELEASE_DIR}" ] || (echo "Unable to locate extracted Liferay directory" && exit 1); \
    cp -a "${RELEASE_DIR}/." "${LIFERAY_HOME}/"; \
    find /tmp/liferay-bundle -maxdepth 1 -type f -name '*.xml' -exec cp {} "${LIFERAY_HOME}/deploy/" \; || true; \
    rm -rf "${TMP_EXTRACT}" /tmp/liferay-bundle

# Copy Bouncy Castle FIPS jars and database driver
RUN mkdir -p ${LIFERAY_HOME}/tomcat/lib ${LIFERAY_HOME}/tomcat/webapps/ROOT/WEB-INF/shielded-container-lib ${LIFERAY_HOME}/data
COPY liferay/configs/bouncycastle/*.jar ${LIFERAY_HOME}/tomcat/lib/
COPY liferay/configs/jdbc-driver/*.jar ${LIFERAY_HOME}/tomcat/lib/

# Override java.security with the FIPS-aware configuration
COPY liferay/configs/jdk/java.security ${LIFERAY_HOME}/java.security

# Configure Liferay (OSGi, portal properties, portal key material)
COPY liferay/configs/osgi/configs/*.config ${LIFERAY_HOME}/osgi/configs/
COPY liferay/configs/portal/portal-ext.properties ${LIFERAY_HOME}/
COPY liferay/configs/portal/fips.key ${LIFERAY_HOME}/data/fips.key
RUN chmod 600 ${LIFERAY_HOME}/data/fips.key

# Tomcat configuration (Context, Server, security assets)
COPY liferay/configs/tomcat/context.xml ${LIFERAY_HOME}/tomcat/conf/context.xml
COPY liferay/configs/tomcat/server.xml ${LIFERAY_HOME}/tomcat/conf/server.xml
COPY liferay/configs/tomcat/setenv.sh ${LIFERAY_HOME}/tomcat/bin/setenv.sh
COPY liferay/configs/tomcat/run-java-wrapper.sh ${LIFERAY_HOME}/tomcat/bin/run-java-wrapper.sh
COPY liferay/configs/tomcat/support ${LIFERAY_HOME}/tomcat/support-src
RUN set -eux; \
    chmod +x ${LIFERAY_HOME}/tomcat/bin/setenv.sh ${LIFERAY_HOME}/tomcat/bin/run-java-wrapper.sh; \
    mkdir -p ${LIFERAY_HOME}/tomcat/support-classes; \
    javac -cp ${LIFERAY_HOME}/tomcat/lib/catalina.jar \
        -d ${LIFERAY_HOME}/tomcat/support-classes \
        ${LIFERAY_HOME}/tomcat/support-src/*.java; \
    jar cfm ${LIFERAY_HOME}/tomcat/lib/tomcat-url-handler-disabler.jar \
        ${LIFERAY_HOME}/tomcat/support-src/MANIFEST.MF \
        -C ${LIFERAY_HOME}/tomcat/support-classes .; \
    rm -rf ${LIFERAY_HOME}/tomcat/support-src ${LIFERAY_HOME}/tomcat/support-classes

# Overlay patched SecureRandomUtil directly into portal-kernel (built from security-ext)
COPY security-ext/build/classes/java/main/com/liferay/portal/kernel/security/ /tmp/patches/com/liferay/portal/kernel/security/
RUN set -eux; \
    cd ${LIFERAY_HOME}/tomcat/webapps/ROOT/WEB-INF/shielded-container-lib; \
    jar uf portal-kernel.jar -C /tmp/patches com; \
    rm -rf /tmp/patches

# User-provided keystores/truststores
COPY liferay/configs/tomcat/security/keystore.bcfks ${LIFERAY_HOME}/tomcat/conf/keystore.bcfks
COPY liferay/configs/tomcat/security/fips-truststore.bcfks ${LIFERAY_HOME}/tomcat/conf/fips-truststore.bcfks

# Ensure correct ownership of all files
RUN chown -R ${LIFERAY_USER}:${LIFERAY_GROUP} ${LIFERAY_HOME}

USER ${LIFERAY_USER}
EXPOSE 8000 8080 8443 11311

CMD ["/opt/liferay/tomcat/bin/catalina.sh", "run"]
