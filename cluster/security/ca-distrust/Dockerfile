ARG BASE_IMAGE
ARG PYTHON_BUILDER=docker.io/library/python:3.13-slim-bookworm@sha256:a881a81282cca8c57f97014867fa651def1b3799030cc6b1cff45ed55ba8ef36

FROM ${BASE_IMAGE} AS source

FROM ${PYTHON_BUILDER} AS filtered
COPY filter_ca_bundle.py /usr/local/bin/filter_ca_bundle.py
COPY --from=source /etc/ssl/certs/ca-certificates.crt /tmp/ca-certificates.crt
RUN python /usr/local/bin/filter_ca_bundle.py /tmp/ca-certificates.crt /out/ca-certificates.crt

FROM ${BASE_IMAGE}
COPY --from=filtered /out/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=filtered /out/ca-certificates.crt /etc/ssl/kloud-ca/ca-certificates.crt
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
    SSL_CERT_DIR=/etc/ssl/kloud-ca
