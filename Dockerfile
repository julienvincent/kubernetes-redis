FROM alpine:3.4
MAINTAINER Julien Vincent <julien.vincent@onedayonly.co.za>

RUN apk add --no-cache redis sed bash jq curl

COPY container/redis-master.conf /redis-master/redis.conf
COPY container/redis-slave.conf /redis-slave/redis.conf
COPY container/run.sh /run.sh

CMD [ "/run.sh" ]
ENTRYPOINT [ "bash", "-c" ]
