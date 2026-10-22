# Legacy CA images

These images preserve the captured deployed application image and version while
removing only the two distrusted CA roots. CouchDB uses a dedicated Dockerfile
because Erlang OTP 24 replication reads its CA file from CouchDB's
`ssl_trusted_certificates_file` option; the derived image enables replication
certificate verification and points it at the filtered bundle. Inbound CouchDB
TLS configuration is unchanged.

MinIO could not be rebuilt from its captured multi-architecture index because
the matching ARM64 layer is unavailable from the upstream registry. The
filtered trust bundle captured from the deployed MinIO image is stored in
`minio-ca/ca-certificates.bundle`; `minio-ca/projection.json` records its source
index, digest, and removed-root counts. The deployment patch can project this
file while preserving the original application image.
