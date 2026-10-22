ARG BASE_IMAGE
ARG PYTHON_BUILDER=docker.io/library/python:3.13-slim-bookworm@sha256:a881a81282cca8c57f97014867fa651def1b3799030cc6b1cff45ed55ba8ef36

FROM ${BASE_IMAGE} AS source

FROM ${BASE_IMAGE} AS java-filtered
COPY minecraft/filter_java_cacerts.sh /usr/local/bin/filter_java_cacerts.sh
RUN java_home="${JAVA_HOME:-$(java -XshowSettings:properties -version 2>&1 | awk '/^[[:space:]]*java\.home =/ { print $3; exit }')}"; \
	test -n "$java_home"; \
	/bin/sh /usr/local/bin/filter_java_cacerts.sh \
		"$java_home/lib/security/cacerts" /out/cacerts

FROM ${PYTHON_BUILDER} AS os-filtered
COPY filter_ca_bundle.py /usr/local/bin/filter_ca_bundle.py
COPY --from=source /etc/ssl/certs/ca-certificates.crt /tmp/ca-certificates.crt
RUN python /usr/local/bin/filter_ca_bundle.py /tmp/ca-certificates.crt /out/ca-certificates.crt

FROM ${BASE_IMAGE}
COPY --from=os-filtered /out/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=os-filtered /out/ca-certificates.crt /etc/ssl/kloud-ca/ca-certificates.crt
COPY --from=java-filtered /out/cacerts /tmp/kloud-cacerts
RUN set -eu; \
	java_home="${JAVA_HOME:-$(java -XshowSettings:properties -version 2>&1 | awk '/^[[:space:]]*java\.home =/ { print $3; exit }')}"; \
	test -n "$java_home"; \
	cat /tmp/kloud-cacerts > "$java_home/lib/security/cacerts"; \
	cmp -s /tmp/kloud-cacerts "$java_home/lib/security/cacerts"; \
	rm /tmp/kloud-cacerts
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt \
	SSL_CERT_DIR=/etc/ssl/kloud-ca
