FROM alpine:3.22

RUN sed -i 's|https://dl-cdn.alpinelinux.org/alpine|https://mirror.yandex.ru/mirrors/alpine|' /etc/apk/repositories \
    && apk add --no-cache build-base

WORKDIR /work
CMD ["sh", "build.sh", "hello.c"]
