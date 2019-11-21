FROM alpine:latest
USER root
ARG _WKDIR=/usr/local/share/fossology-rest-api/
WORKDIR $_WKDIR
COPY json-templates $_WKDIR/json-templates
COPY upload-rest.sh $_WKDIR/
# Enable to copy your CA Certificate
#COPY ca-certificates.crt $_WKDIR/
RUN export PATH=$PATH:$_WKDIR
RUN apk add jq
RUN apk add curl

