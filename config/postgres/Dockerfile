FROM postgres:18@sha256:86c951e05bf56c93d95d397747fb8820ac76cc3bedb78f43abd83eedbe3666ae

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg \
    && install -d -m 0755 /usr/share/postgresql-common/pgdg \
    && curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --batch --yes --dearmor -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg \
    && echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.gpg] https://apt.postgresql.org/pub/repos/apt trixie-pgdg main" > /etc/apt/sources.list.d/pgdg.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends patroni python3-etcd pgbackrest \
    && rm -rf /var/lib/apt/lists/*

# The upstream image's uid/gid 999 collides with host service accounts (on Groot
# it is node_exporter, and the MySQL and Redis containers' data owner). Host
# data directories and the pgBackRest NFS repository are owned by this
# dedicated id instead. Change it only together with a chown of every member's
# data directory and the repository.
ARG POSTGRES_UID=5432
ARG POSTGRES_GID=5432
RUN groupmod -g "${POSTGRES_GID}" postgres \
    && usermod -u "${POSTGRES_UID}" -g "${POSTGRES_GID}" postgres \
    && find / -xdev \( -uid 999 -o -gid 999 \) -exec chown -h postgres:postgres {} + \
    && test "$(id -u postgres):$(id -g postgres)" = "${POSTGRES_UID}:${POSTGRES_GID}"

# pgBackRest is configured only through PGBACKREST_* environment variables (see
# config/deploy.campsite-pg.yml), which docker exec sessions and PostgreSQL's
# archive_command both inherit. Empty the packaged sample so its demo stanza
# and repo path cannot apply.
RUN : > /etc/pgbackrest.conf

COPY patroni.yml.tmpl /etc/patroni/patroni.yml.tmpl
COPY entrypoint.sh /usr/local/bin/campsite-postgres-ha-entrypoint
RUN chmod 0755 /usr/local/bin/campsite-postgres-ha-entrypoint \
    && install -d -o postgres -g postgres -m 0700 /run/patroni

USER postgres
ENTRYPOINT ["/usr/local/bin/campsite-postgres-ha-entrypoint"]
CMD ["patroni", "/run/patroni/patroni.yml"]
