FROM nginx:stable

ADD ./docker/nginx/default.conf /etc/nginx/conf.d/default.conf
ADD ./docker/nginx/certs /etc/nginx/certs/self-signed

RUN mkdir -p /var/www/html
