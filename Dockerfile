# FROM openresty/openresty:1.21.4.2-alpine AS builder
# FROM openresty/openresty:1.27.1.2-alpine AS builder
FROM stu2116edwardhu/openresty:latest AS builder
USER root
RUN mkdir /app
WORKDIR /app

ADD stats.lua    /app
ADD protect.lua  /app
ADD record.lua   /app

# FROM --platform=linux/amd64 openresty/openresty:1.21.4.2-alpine
# FROM openresty/openresty:1.21.4.2-alpine
FROM stu2116edwardhu/openresty:latest
EXPOSE 80 443 3000

USER root
RUN mkdir /app
WORKDIR /app
RUN apk add --no-cache tzdata
ENV TZ=Asia/Shanghai

ADD stats.lua       /app/stats.lua
ADD protect.lua     /app/protect.lua
ADD record.lua      /app/record.lua
ADD cert.key        /app/cert.key
ADD cert.crt        /app/cert.crt
ADD env.conf        /app/env.conf
ADD nginx.conf      /app/nginx.conf

# 更改文件权限给 nobody
RUN chown -R nobody:nobody /app

# 切换到非 root 用户
USER nobody

CMD ["openresty", "-c", "/app/nginx.conf"]
