FROM ubuntu:14.04

RUN apt-get update
RUN apt-get install -y wget nginx build-essential pwgen \
    python-pip python-dev \
    postgresql-9.3 postgresql-server-dev-9.3 \
    redis-server \
    nginx

# Setup supervisord + sysv init startup script
RUN sudo -u redash mkdir -p /opt/redash/supervisord
RUN pip install supervisor==3.1.2 # TODO: move to requirements.txt

# BigQuery dependencies:
RUN apt-get install -y libffi-dev libssl-dev
RUN pip install google-api-python-client==1.2 pyOpenSSL==0.14 oauth2client==1.2

# MySQL dependencies:
RUN apt-get install -y libmysqlclient-dev
RUN pip install MySQL-python==1.2.5

# Mongo dependencies:
RUN pip install pymongo==2.7.2

ADD . /redash

ENV REDIS_PORT=6379
ENV REDIS_CONFIG_FILE="/etc/redis/$REDIS_PORT.conf"
ENV REDIS_LOG_FILE="/var/log/redis_$REDIS_PORT.log"
ENV REDIS_DATA_DIR="/var/lib/redis/$REDIS_PORT"

ENV mkdir -p `dirname "$REDIS_CONFIG_FILE"` || die "Could not create redis config directory"
ENV mkdir -p `dirname "$REDIS_LOG_FILE"` || die "Could not create redis log dir"
ENV mkdir -p "$REDIS_DATA_DIR" || die "Could not create redis data directory"

ENV wget -O /etc/init.d/redis_6379 $FILES_BASE_URL"redis_init"
ENV wget -O $REDIS_CONFIG_FILE $FILES_BASE_URL"redis.conf"


RUN adduser --system --no-create-home --disabled-login --gecos "" redash

add_service() {
    service_name=$1
    service_command="/etc/init.d/$service_name"

    echo "Adding service: $service_name (/etc/init.d/$service_name)."
    chmod +x $service_command

    if command -v chkconfig >/dev/null 2>&1; then
        # we're chkconfig, so lets add to chkconfig and put in runlevel 345
        chkconfig --add $service_name && echo "Successfully added to chkconfig!"
        chkconfig --level 345 $service_name on && echo "Successfully added to runlevels 345!"
    elif command -v update-rc.d >/dev/null 2>&1; then
        #if we're not a chkconfig box assume we're able to use update-rc.d
        update-rc.d $service_name defaults && echo "Success!"
    else
        echo "No supported init tool found."
    fi

    $service_command start
}

RUN mkdir /opt/redash
RUN chown redash /opt/redash
RUN -u redash mkdir /opt/redash/logs

# Default config file
RUN -u redash wget $FILES_BASE_URL"env" -O /opt/redash/.env

# Install latest version
# REDASH_VERSION=${REDASH_VERSION-0.4.0.b589}
# modified by @fedex1 3/15/2015 seems to be the latest version at this point in time.
REDASH_VERSION=${REDASH_VERSION-0.6.0.b722}
LATEST_URL="https://github.com/EverythingMe/redash/releases/download/v${REDASH_VERSION/.b/%2Bb}/redash.$REDASH_VERSION.tar.gz"
VERSION_DIR="/opt/redash/redash.$REDASH_VERSION"
REDASH_TARBALL=/tmp/redash.tar.gz
REDASH_TARBALL=/tmp/redash.tar.gz

if [ ! -d "$VERSION_DIR" ]; then
    sudo -u redash wget $LATEST_URL -O $REDASH_TARBALL
    sudo -u redash mkdir $VERSION_DIR
    sudo -u redash tar -C $VERSION_DIR -xvf $REDASH_TARBALL
    ln -nfs $VERSION_DIR /opt/redash/current
    ln -nfs /opt/redash/.env /opt/redash/current/.env

    cd /opt/redash/current

    # TODO: venv?
    pip install -r requirements.txt
fi

service postgresql start

# Create database / tables
pg_user_exists=0
sudo -u postgres psql postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='redash'" | grep -q 1 || pg_user_exists=$?
if [ $pg_user_exists -ne 0 ]; then
    echo "Creating redash postgres user & database."
    sudo -u postgres createuser redash --no-superuser --no-createdb --no-createrole
    sudo -u postgres createdb redash --owner=redash

    cd /opt/redash/current
    sudo -u redash bin/run ./manage.py database create_tables
fi

# Create default admin user
cd /opt/redash/current
# TODO: make sure user created only once
# TODO: generate temp password and print to screen
sudo -u redash bin/run ./manage.py users create --admin --password admin "Admin" "admin"

# Create re:dash read only pg user & setup data source
pg_user_exists=0
sudo -u postgres psql postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='redash_reader'" | grep -q 1 || pg_user_exists=$?
if [ $pg_user_exists -ne 0 ]; then
    echo "Creating redash reader postgres user."
    REDASH_READER_PASSWORD=$(pwgen -1)
    sudo -u postgres psql -c "CREATE ROLE redash_reader WITH PASSWORD '$REDASH_READER_PASSWORD' NOCREATEROLE NOCREATEDB NOSUPERUSER LOGIN"
    sudo -u redash psql -c "grant select(id,name,type) ON data_sources to redash_reader;" redash
    sudo -u redash psql -c "grant select on activity_log, events, queries, dashboards, widgets, visualizations, query_results to redash_reader;" redash

    cd /opt/redash/current
    sudo -u redash bin/run ./manage.py ds new -n "re:dash metadata" -t "pg" -o "{\"user\": \"redash_reader\", \"password\": \"$REDASH_READER_PASSWORD\", \"host\": \"localhost\", \"dbname\": \"redash\"}"
fi


# Get supervisord startup script
sudo -u redash wget -O /opt/redash/supervisord/supervisord.conf $FILES_BASE_URL"supervisord.conf"

wget -O /etc/init.d/redash_supervisord $FILES_BASE_URL"redash_supervisord_init"
add_service "redash_supervisord"

# Nginx setup
rm /etc/nginx/sites-enabled/default
wget -O /etc/nginx/sites-available/redash $FILES_BASE_URL"nginx_redash_site"
ln -nfs /etc/nginx/sites-available/redash /etc/nginx/sites-enabled/redash
service nginx restart

ENTRYPOINT redis && redash_supervisord

CMD nginx
