FROM rafaelpraxedesliferayorg/dhi-eclipse-temurin:21.0-jdk-debian13-dev

ENV LIFERAY_HOME=/opt/liferay
ENV LIFERAY_USER=liferay
ENV LIFERAY_GROUP=liferay
ENV LIFERAY_UID=1001
ENV LIFERAY_GID=1001

RUN apt-get update && \
   apt-get install -y --no-install-recommends gzip tree unzip && \
   rm -rf /var/lib/apt/lists/*

RUN groupadd -g ${LIFERAY_GID} ${LIFERAY_GROUP} && \
   useradd -u ${LIFERAY_UID} -g ${LIFERAY_GID} -m -d ${LIFERAY_HOME} -s /bin/bash ${LIFERAY_USER}

WORKDIR ${LIFERAY_HOME}

COPY --chown=${LIFERAY_USER}:${LIFERAY_GROUP} /bundle/*.zip .
RUN unzip *.zip && mv liferay-dxp*/* . && rm -rf liferay-dxp* *.zip

# Copy Bouncycastle's JARs
COPY --chown=${LIFERAY_USER}:${LIFERAY_GROUP} configs/bouncycastle/*.jar tomcat/lib/

# Copy mySQL's JDBC driver
COPY --chown=${LIFERAY_USER}:${LIFERAY_GROUP} configs/jdbc-driver/*.jar /opt/liferay/tomcat/webapps/ROOT/WEB-INF/shielded-container-lib

# Set boundycastle provider as the default java security provider
COPY --chown=${LIFERAY_USER}:${LIFERAY_GROUP} configs/jdk/java.security ${LIFERAY_HOME}/

# Setup elastic search as remote service
COPY --chown=${LIFERAY_USER}:${LIFERAY_GROUP} configs/osgi/configs/*.config osgi/configs

# Set tomcat setenv.sh
COPY --chown=${LIFERAY_USER}:${LIFERAY_GROUP} configs/tomcat/jvm.options ${LIFERAY_HOME}/jvm.options.temp

RUN cat ${LIFERAY_HOME}/jvm.options.temp >> tomcat/bin/setenv.sh && \
    rm ${LIFERAY_HOME}/jvm.options.temp

# Copy Liferay's portal-ext.properties
 COPY --chown=${LIFERAY_USER}:${LIFERAY_GROUP} configs/portal/portal-ext.properties ${LIFERAY_HOME}/

# Ensure correct ownership of all files
RUN chown -R ${LIFERAY_USER}:${LIFERAY_GROUP} ${LIFERAY_HOME}

ENV JAVA_HOME=/opt/java/openjdk/21

USER ${LIFERAY_USER}
EXPOSE 8000
EXPOSE 8080
EXPOSE 11311

# Start Liferay using Tomcat's catalina.sh
CMD ["/opt/liferay/tomcat/bin/catalina.sh", "run"]