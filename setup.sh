#!/bin/bash

BC_FIPS_JAR="bc-fips-2.1.2.jar"
BC_UTIL_JAR="bcutil-fips-2.1.5.jar"
BC_DIR="liferay/configs/bouncycastle"
PROVIDERS="${BC_DIR}/${BC_FIPS_JAR}:${BC_DIR}/${BC_UTIL_JAR}"

LIFERAY_RELEASES_CDN_URL=https://releases-cdn.liferay.com

patching_secure_random_util(){
    tar -xOf liferay/bundle/$DXP_TOMCAT_BUNDLE_NAME \
        liferay-dxp/tomcat/webapps/ROOT/WEB-INF/shielded-container-lib/portal-kernel.jar \
        > security-ext/lib/portal-kernel.jar

    docker run --rm -u root \
        -v "$PWD":/home/gradle/project \
        -w /home/gradle/project/security-ext \
        gradle:8-jdk17 gradle clean war
}

setup_dxp_tomcat(){    
    DXP_TOMCAT_BUNDLE_TIMESTAMP=$(\
        curl $LIFERAY_RELEASES_CDN_URL/dxp/${DXP_TOMCAT_BUNDLE_VERSION}/release.properties | \
        awk -F'=' '/build\.timestamp=/ {print $2}')
    DXP_TOMCAT_BUNDLE_URL="$LIFERAY_RELEASES_CDN_URL/dxp/$DXP_TOMCAT_BUNDLE_VERSION/liferay-dxp-tomcat-$DXP_TOMCAT_BUNDLE_VERSION-$DXP_TOMCAT_BUNDLE_TIMESTAMP.tar.gz"
    DXP_TOMCAT_BUNDLE_NAME="$DXP_TOMCAT_BUNDLE_VERSION-$DXP_TOMCAT_BUNDLE_TIMESTAMP.tar.gz"

    if [ -z $DXP_TOMCAT_BUNDLE_TIMESTAMP ]; then
        echo "Could not find $DXP_TOMCAT_BUNDLE_VERSION on $LIFERAY_RELEASES_CDN_URL." >&2
        exit 1
    fi

    if [ ! -e $PWD/liferay/bundle/$DXP_TOMCAT_BUNDLE_NAME ]; then
        echo "Downloading $DXP_TOMCAT_BUNDLE_NAME from $DXP_TOMCAT_BUNDLE_URL."
        wget $DXP_TOMCAT_BUNDLE_URL -O $PWD/liferay/bundle/$DXP_TOMCAT_BUNDLE_NAME
    fi

    echo "Copying activation key from $ACTIVATION_KEY_PATH into ./liferay/bundle/"
    cp $ACTIVATION_KEY_PATH "$PWD/liferay/bundle/"
}

generate_mysql_certs() {
    echo "Creating MySQL certificates..."
    pushd mysql/certs > /dev/null
    
    openssl genrsa -out ca-key.pem 4096
    openssl req -x509 -new -key ca-key.pem -sha384 -days 3650 -out ca.pem -subj "/CN=mysql-ca"
    
    openssl genrsa -out server-key.pem 4096
    openssl req -new -key server-key.pem -out server.csr -subj "/CN=database" \
      -addext "subjectAltName=DNS:database,IP:127.0.0.1"
      
    openssl x509 -req -in server.csr -CA ca.pem -CAkey ca-key.pem -CAcreateserial \
      -out server-cert.pem -days 825 -sha384 -extensions san \
      -extfile <(printf "[san]\nsubjectAltName=DNS:database,IP:127.0.0.1")
      
    chmod 600 server-key.pem
    rm -f ca-key.pem server.csr server.srl
    popd > /dev/null
}

generate_elastic_certs() {
    echo "Creating Elasticsearch certificates..."
    pushd elasticsearch/certs > /dev/null
    
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
    rm -f elastic-ca.key elastic-node.csr elastic-ca.srl
    popd > /dev/null
}

generate_liferay_artifacts() {
    echo "Creating Liferay portal key and BCFKS stores..."
    
    # Generate 32-byte AES key for the portal
    openssl rand -out liferay/configs/portal/fips.key 32

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
      if [ -f "$CA" ]; then
          echo "Importing $CA into truststore..."
          keytool -importcert -noprompt \
            -alias "$(basename "$CA")" \
            -file "$CA" \
            -storepass "$FIPS_TRUSTSTORE_PASSWORD" \
            -keystore liferay/configs/tomcat/security/fips-truststore.bcfks \
            -storetype BCFKS \
            -providerclass org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider \
            -providerpath "${PROVIDERS}"
      else
          echo "Warning: $CA not found, skipping import."
      fi
    done
}

override_credentials_on_configs() {
  ELASTIC_SEARCH_CONFIG=com.liferay.portal.search.elasticsearch7.configuration.ElasticsearchConfiguration.config
  SQL_CREATE_USER_FILE=01-create-liferay.sql
  
  sed -i "3s/liferay/$JNDI_DB_USERNAME/g; 4s/liferay/$JNDI_DB_PASSWORD/g; 5s/liferay/$JNDI_DB_USERNAME/g" mysql/initdb.d/$SQL_CREATE_USER_FILE
  sed -i "8s/elasticFips!2024/$ELASTIC_PASSWORD/g; 11s/liferay/$FIPS_TRUSTSTORE_PASSWORD/g" liferay/configs/osgi/configs/$ELASTIC_SEARCH_CONFIG

  echo -e "Overrided credentials on files: $SQL_CREATE_USER_FILE and $ELASTIC_SEARCH_CONFIG"
}

main() {
    set -e
    
    if [ -f .env ]; then
      echo -e "\n### Loading .env file"
      export $(echo $(cat .env | sed 's/#.*//g' | xargs))
    fi

    env_vars=(
      "LIFERAY_BASE_IMAGE" "ELASTIC_PASSWORD" "JNDI_DB_USERNAME" 
      "JNDI_DB_PASSWORD" "DXP_TOMCAT_BUNDLE_VERSION" "ACTIVATION_KEY_PATH"
      "TOMCAT_KEYSTORE_PASSWORD" "FIPS_TRUSTSTORE_PASSWORD"
    )

    for var in "${env_vars[@]}"; do
        if [ -z "${!var}" ]; then
            echo "$var is NOT set"
            exit 1
        fi
    done
        
    echo -e "\n### Clearing DXP Tomcat BCFKS"
    rm -f $PWD/liferay/configs/tomcat/security/*.bcfks

    echo -e "\n### Setting up DXP Tomcat"
    echo -e "Looking for DXP Tomcat $DXP_TOMCAT_BUNDLE_VERSION version on $LIFERAY_RELEASES_CDN_URL.."
    setup_dxp_tomcat

    echo -e "\n### Setting up FIPS artifacts"
    generate_mysql_certs
    generate_elastic_certs
    generate_liferay_artifacts

    echo -e "\n### Setting up extra steps"
    override_credentials_on_configs
    patching_secure_random_util
}

main
