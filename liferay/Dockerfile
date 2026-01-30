############################
# Stage 1 — Builder
############################
ARG BUILDER_IMAGE=testhdimg/dhi-eclipse-temurin:21-jdk-debian13-dev
FROM ${BUILDER_IMAGE} AS builder

ENV LIFERAY_HOME=/opt/liferay \
    LIFERAY_UID=1001 \
    LIFERAY_GID=1001 \
    JAVA_HOME=/opt/java/openjdk/21

ARG TOMCAT_KEYSTORE_PASSWORD=changeit
ARG JNDI_DB_USERNAME=root

ENV TOMCAT_KEYSTORE_PASSWORD=${TOMCAT_KEYSTORE_PASSWORD} \
    JNDI_DB_USERNAME=${JNDI_DB_USERNAME}

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        ca-certificates gzip tar unzip tree && \
    rm -rf /var/lib/apt/lists/*

WORKDIR ${LIFERAY_HOME}

# --- extract Liferay bundle ---
COPY liferay/bundle /tmp/liferay-bundle
RUN set -eux; \
    mkdir -p "${LIFERAY_HOME}/deploy"; \
    ARCHIVE="$(find /tmp/liferay-bundle -maxdepth 1 -type f \( -name '*.tar.gz' -o -name '*.tgz' -o -name '*.zip' \) | head -n 1)"; \
    [ -n "${ARCHIVE}" ] || (echo "No bundle found" && exit 1); \
    TMP_EXTRACT="$(mktemp -d)"; \
    case "${ARCHIVE}" in \
        *.zip) unzip -q "${ARCHIVE}" -d "${TMP_EXTRACT}";; \
        *.tar.gz|*.tgz) tar -xzf "${ARCHIVE}" -C "${TMP_EXTRACT}";; \
    esac; \
    RELEASE_DIR="$(find "${TMP_EXTRACT}" -maxdepth 1 -type d -name 'liferay-*' -print -quit)"; \
    cp -a "${RELEASE_DIR}/." "${LIFERAY_HOME}/"; \
    find /tmp/liferay-bundle -maxdepth 1 -type f -name '*.xml' -exec cp {} "${LIFERAY_HOME}/deploy/" \; || true; \
    rm -rf "${TMP_EXTRACT}" /tmp/liferay-bundle

# --- directories ---
RUN mkdir -p \
    ${LIFERAY_HOME}/tomcat/lib \
    ${LIFERAY_HOME}/tomcat/webapps/ROOT/WEB-INF/shielded-container-lib \
    ${LIFERAY_HOME}/data

# --- libraries ---
COPY liferay/configs/bouncycastle/*.jar ${LIFERAY_HOME}/tomcat/lib/
COPY liferay/configs/jdbc-driver/*.jar ${LIFERAY_HOME}/tomcat/lib/

# --- configs ---
COPY liferay/configs/jdk/java.security ${LIFERAY_HOME}/java.security
COPY liferay/configs/osgi/configs/*.config ${LIFERAY_HOME}/osgi/configs/
COPY liferay/configs/portal/portal-ext.properties ${LIFERAY_HOME}/
COPY liferay/configs/portal/fips.key ${LIFERAY_HOME}/data/fips.key

# --- tomcat config ---
COPY liferay/configs/tomcat/context.xml ${LIFERAY_HOME}/tomcat/conf/context.xml
COPY liferay/configs/tomcat/server.xml ${LIFERAY_HOME}/tomcat/conf/server.xml
COPY liferay/configs/tomcat/setenv.sh ${LIFERAY_HOME}/tomcat/bin/setenv.sh
COPY liferay/configs/tomcat/run-java-wrapper.sh ${LIFERAY_HOME}/tomcat/bin/run-java-wrapper.sh
COPY liferay/configs/tomcat/support ${LIFERAY_HOME}/tomcat/support-src

# --- compile support classes (needs JDK) ---
RUN set -eux; \
    chmod +x ${LIFERAY_HOME}/tomcat/bin/*.sh; \
    mkdir -p ${LIFERAY_HOME}/tomcat/support-classes; \
    javac -cp ${LIFERAY_HOME}/tomcat/lib/catalina.jar \
        -d ${LIFERAY_HOME}/tomcat/support-classes \
        ${LIFERAY_HOME}/tomcat/support-src/*.java; \
    jar cfm ${LIFERAY_HOME}/tomcat/lib/tomcat-url-handler-disabler.jar \
        ${LIFERAY_HOME}/tomcat/support-src/MANIFEST.MF \
        -C ${LIFERAY_HOME}/tomcat/support-classes .; \
    rm -rf ${LIFERAY_HOME}/tomcat/support-src ${LIFERAY_HOME}/tomcat/support-classes

# --- patch portal-kernel ---
COPY security-ext/build/classes/java/main/com/liferay/portal/kernel/security/ /tmp/patches/com/liferay/portal/kernel/security/
RUN set -eux; \
    cd ${LIFERAY_HOME}/tomcat/webapps/ROOT/WEB-INF/shielded-container-lib; \
    jar uf portal-kernel.jar -C /tmp/patches com; \
    rm -rf /tmp/patches

# --- security stores ---
COPY liferay/configs/tomcat/security/*.bcfks ${LIFERAY_HOME}/tomcat/conf/
COPY liferay/configs/tomcat/root/fips_verify.jsp ${LIFERAY_HOME}/tomcat/webapps/ROOT/

# --- permissions (numeric, no named user needed) ---
RUN chmod 600 ${LIFERAY_HOME}/data/fips.key || true
RUN chown -R ${LIFERAY_UID}:${LIFERAY_GID} ${LIFERAY_HOME}


############################
# Stage 2 — FIPS Runtime (no shell)
############################
FROM testhdimg/dhi-eclipse-temurin:21-debian13-fips

ENV LIFERAY_HOME=/opt/liferay

WORKDIR /opt/liferay

COPY --from=builder /opt/liferay /opt/liferay

# run as non-root numeric user
USER 1001:1001

EXPOSE 8000 8080 8443 11311

# no shell available → start Tomcat directly via Java
CMD [
  "java",
  "-Dcatalina.base=/opt/liferay/tomcat",
  "-Dcatalina.home=/opt/liferay/tomcat",
  "-Djava.io.tmpdir=/opt/liferay/tomcat/temp",
  "org.apache.catalina.startup.Bootstrap",
  "start"
]