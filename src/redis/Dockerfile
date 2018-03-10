FROM redis:4-alpine

LABEL maintainer="Claudio Netto <nettoclaudio@ufrj.br>"

COPY --chown=redis:redis files/redis-ha-entrypoint.sh /

RUN chmod 540 /redis-ha-entrypoint.sh

USER redis

ENTRYPOINT [ "/redis-ha-entrypoint.sh" ]