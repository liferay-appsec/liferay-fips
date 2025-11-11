ARG ELASTIC_BASE_IMAGE=docker.elastic.co/elasticsearch/elasticsearch:8.17.2
FROM ${ELASTIC_BASE_IMAGE}

USER root

COPY elasticsearch/config/elasticsearch.yml /usr/share/elasticsearch/config/elasticsearch.yml
COPY elasticsearch/certs/ /usr/share/elasticsearch/config/certs/

RUN chown -R elasticsearch:elasticsearch /usr/share/elasticsearch/config && \
    chmod 600 /usr/share/elasticsearch/config/certs/elastic-node.key

USER elasticsearch

RUN bin/elasticsearch-plugin install --batch analysis-icu && \
    bin/elasticsearch-plugin install --batch analysis-kuromoji && \
    bin/elasticsearch-plugin install --batch analysis-smartcn && \
    bin/elasticsearch-plugin install --batch analysis-stempel
