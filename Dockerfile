FROM ubuntu:14.04
MAINTAINER javed<i@javed.cn>
ENV NGINX_VERSION 1.12.1-1~trusty
ENV SOFTWARE_TEMP_DIR /SOFTWARE_TEMP_DIR
ENV WWW_ROOT /data/www/
#用bash替代sh
RUN rm /bin/sh &&  ln -s /bin/bash /bin/sh
#设置时区
RUN cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
#替换源镜像地址
RUN sed -i "s/archive.ubuntu.com/cn.archive.ubuntu.com/g" /etc/apt/sources.list
#安装NGINX
RUN apt-key adv --keyserver hkp://pgp.mit.edu:80 --recv-keys 573BFD6B3D8FBC641079A6ABABF5BD827BD9BF62 \
	&& echo "deb http://nginx.org/packages/ubuntu/ trusty nginx" >> /etc/apt/sources.list \
	&& apt-get update
RUN apt-get install --no-install-recommends --no-install-suggests -y \
						ca-certificates \
						nginx=${NGINX_VERSION} \
						nginx-module-xslt \
						nginx-module-geoip \
						nginx-module-image-filter \
						nginx-module-perl \
						nginx-module-njs \
						gettext-base
#NGINX 配置
ADD ./conf/nginx.conf /etc/nginx/nginx.conf
ADD ./conf/default.nginx.conf /etc/nginx/conf.d/default.conf
# forward request and error logs to docker log collector
RUN ln -sf /dev/stdout /var/log/nginx/access.log \
	&& ln -sf /dev/stderr /var/log/nginx/error.log
# PHP
# persistent / runtime deps
ENV PHPIZE_DEPS \
		autoconf \
		file \
    #编译用包 有了它 gcc g++ make等都安装了
		build-essential \
		libc-dev \
        libcurl4-openssl-dev \
		libedit-dev \
		#libsqlite3-dev \
		libssl-dev \
		libxml2-dev \
		pkg-config \
		re2c
RUN apt-get install -y \
		$PHPIZE_DEPS \
		ca-certificates \
		curl \
		libedit2 \
		libxml2 \
        libsasl2-dev \
		xz-utils \
        cloog-ppl \
        openssl \
        libssl-dev \
        --no-install-recommends

RUN mkdir -p $SOFTWARE_TEMP_DIR
ADD ./software/* $SOFTWARE_TEMP_DIR/
WORKDIR $SOFTWARE_TEMP_DIR/libmcrypt-2.5.6
RUN ./configure && \
    make && \
    make install
#PHP 编译参数
ENV PHP_INI_DIR /usr/local/etc/php
RUN mkdir -p $PHP_INI_DIR/conf.d
ENV PHP_EXTRA_CONFIGURE_ARGS \
    --with-config-file-path="$PHP_INI_DIR" \
	--with-config-file-scan-dir="$PHP_INI_DIR/conf.d" \
    --enable-fpm \
    --enable-mbstring \
    --enable-mysqlnd \
    --with-curl \
    --with-libedit \
    --with-openssl \
    --with-zlib \
    --with-mcrypt \
    --with-mysql \
    --with-mysqli \
    --enable-pdo \
    --with-pdo-mysql \
    --with-gettext \
    --enable-xml \
    #--with-bz2 \
    --enable-zip \
    --with-pdo-mysql
    #ddd
    #ddd
#安装php
WORKDIR $SOFTWARE_TEMP_DIR/php-7.0.12
RUN ./configure $PHP_EXTRA_CONFIGURE_ARGS && \
    make && \
    make install
RUN cp /usr/local/etc/php-fpm.conf.default /usr/local/etc/php-fpm.conf
RUN cp php.ini-production $PHP_INI_DIR/php.ini
#调整php.ini
RUN sed -i "s/;date.timezone =/date.timezone = Asia\/Shanghai/" $PHP_INI_DIR/php.ini
#调整www_conf
ENV www_conf /usr/local/etc/php-fpm.d/www.conf
# RUN sed -i -e "s/;cgi.fix_pathinfo=1/cgi.fix_pathinfo=0/g" ${php_conf} && \
#     sed -i -e "s/upload_max_filesize\s*=\s*2M/upload_max_filesize = 32M/g" ${php_conf} && \
#     sed -i -e "s/post_max_size\s*=\s*8M/post_max_size = 32M/g" ${php_conf} && \
#     sed -i -e "s/variables_order = \"GPCS\"/variables_order = \"EGPCS\"/g" ${php_conf} && \
RUN sed -i -e "s:NONE\/::g" /usr/local/etc/php-fpm.conf && \
    sed -i -e "s/;daemonize\s*=\s*yes/daemonize = no/g" /usr/local/etc/php-fpm.conf
RUN cp /usr/local/etc/php-fpm.d/www.conf.default /usr/local/etc/php-fpm.d/www.conf
RUN sed -i -e "s/;catch_workers_output\s*=\s*yes/catch_workers_output = yes/g" ${www_conf} && \
    sed -i -e "s/pm.start_servers = 2/pm.start_servers = 3/g" ${www_conf} && \
    sed -i -e "s/pm.min_spare_servers = 1/pm.min_spare_servers = 2/g" ${www_conf} && \
    sed -i -e "s/pm.max_spare_servers = 3/pm.max_spare_servers = 4/g" ${www_conf} && \
    sed -i -e "s/pm.max_requests = 500/pm.max_requests = 200/g" ${www_conf} && \
    sed -i -e "s/user = nobody/user = nginx/g" ${www_conf} && \
    sed -i -e "s/group = nobody/group = nginx/g" ${www_conf} && \
    sed -i -e "s/;listen.mode = 0660/listen.mode = 0660/g" ${www_conf} && \
    sed -i -e "s/;listen.owner = nobody/listen.owner = nginx/g" ${www_conf} && \
    sed -i -e "s/;listen.group = nobody/listen.group = nginx/g" ${www_conf} && \
    sed -i -e "s/listen = 127.0.0.1:9000/listen = \/var\/run\/php-fpm.sock/g" ${www_conf} &&\
    sed -i -e "s/^;clear_env = no$/clear_env = no/" ${www_conf}

#安装libmemcached
WORKDIR $SOFTWARE_TEMP_DIR/libmemcached-1.0.18
RUN ./configure --prefix=/usr/local/libmemcached && \
    make && \
    make install

RUN apt-get install pkg-config
#安装memcached
WORKDIR $SOFTWARE_TEMP_DIR/memcached-php7
RUN phpize  && \
    ./configure --with-libmemcached-dir=/usr/local/libmemcached --enable-memcached-sasl && \
    make && \
    make install
RUN echo "extension=memcached.so" >>$PHP_INI_DIR/conf.d/memcached.ini && \
    echo "memcached.use_sasl = 1" >>$PHP_INI_DIR/conf.d/memcached.ini
#安装redis扩展
RUN pecl install redis && \
    echo "extension=redis.so" >>$PHP_INI_DIR/conf.d/redis.ini
#安装vim
RUN apt-get install vim -y
ADD ./conf/.vimrc /root/.vimrc
#设置web 根目录并copy源代码
RUN mkdir -p $WWW_ROOT
ADD ./www/* $WWW_ROOT
#处理善后工作 清理
RUN apt-get install  supervisor -y
ADD ./conf/supervisord.conf /etc/supervisord.conf
RUN apt-get remove gcc g++ make -y
RUN rm -rf /var/lib/apt/lists/*
RUN rm -rf $SOFTWARE_TEMP_DIR
WORKDIR /
EXPOSE 80
CMD ["/usr/bin/supervisord","-n","-c",  "/etc/supervisord.conf"]
