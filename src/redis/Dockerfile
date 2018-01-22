FROM redis:4-alpine

LABEL maintainer="Claudio Netto <nettoclaudio@ufrj.br>"

COPY files/redis-ha-entrypoint.sh /

RUN apk update && \
    apk add bash && \
    rm /var/cache/apk/* && \
    chown -R redis:redis /redis-ha-entrypoint.sh && \
    chmod +x /redis-ha-entrypoint.sh

ENTRYPOINT [ "/redis-ha-entrypoint.sh" ]
