FROM ubuntu:14.04

RUN apt-get update


RUN apt-get install -y wget nginx build-essential pwgen \
    python-pip python-dev \
    postgresql-9.3 postgresql-server-dev-9.3 \
    redis-server \
    nginx

# Setup supervisord + sysv init startup script
RUN pip install supervisor==3.1.2 # TODO: move to requirements.txt

# BigQuery dependencies:
RUN apt-get install -y libffi-dev libssl-dev
RUN pip install google-api-python-client==1.2 pyOpenSSL==0.14 oauth2client==1.2

# MySQL dependencies:
RUN apt-get install -y libmysqlclient-dev
RUN pip install MySQL-python==1.2.5

# Mongo dependencies:
RUN pip install pymongo==2.7.2

ADD requirements.txt /tmp/requirements.txt
RUN pip install -r /tmp/requirements.txt

ADD . /opt/redash/current

RUN mkdir /opt/redash/logs
RUN mkdir /opt/redash/supervisord

# ENV REDIS_PORT=6379
# ENV REDIS_CONFIG_FILE="/etc/redis/$REDIS_PORT.conf"
# ENV REDIS_LOG_FILE="/var/log/redis_$REDIS_PORT.log"
# ENV REDIS_DATA_DIR="/var/lib/redis/$REDIS_PORT"

# ENV mkdir -p `dirname "$REDIS_CONFIG_FILE"` || die "Could not create redis config directory"
# ENV mkdir -p `dirname "$REDIS_LOG_FILE"` || die "Could not create redis log dir"
# ENV mkdir -p "$REDIS_DATA_DIR" || die "Could not create redis data directory"

# ENV wget -O /etc/init.d/redis_6379 $FILES_BASE_URL"redis_init"
# ENV wget -O $REDIS_CONFIG_FILE $FILES_BASE_URL"redis.conf"


# RUN adduser --system --no-create-home --disabled-login --gecos "" redash

RUN rm /etc/nginx/sites-enabled/default
ADD setup/files/nginx_redash_site /etc/nginx/sites-available/redash 
RUN ln -nfs /etc/nginx/sites-available/redash /etc/nginx/sites-enabled/redash

ENTRYPOINT 

CMD supervisord --configuration /opt/redash/current/setup/files/supervisord.conf && \
    service redis-server start && \
    nginx -g "daemon off;"
