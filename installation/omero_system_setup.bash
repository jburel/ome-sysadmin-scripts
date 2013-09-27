#!/bin/bash

set -eux

if [ `id -u` -ne 0 ]; then
    echo "ERROR: Must be run as root"
    exit 2
fi

if [ $# -lt 2 -o $# -gt 3 ]; then
    echo "Usage: `basename $0` instance-name server.zip [omerodump.sql]"
    exit 2
fi

INSTANCE="$1"
SERVERZIP="$2"

if [ ! -f "$SERVERZIP" ]; then
    echo "ERROR: $SERVERZIP does not exist"
    exit 2
fi

OMEROSQL=""
if [ $# -eq 3 ]; then
    OMEROSQL="$3"
    if [ ! -f "$OMEROSQL" ]; then
        echo "ERROR: $OMEROSQL does not exist"
        exit 2
    fi
fi

MEMORY=2048
CREDENTIALS=credentials.txt

echo "Creating user $USERNAME"
# Only accessible via sudo
USERNAME="$INSTANCE"
useradd -m -s /sbin/nologin "$USERNAME"

DBNAME=$INSTANCE
DBUSER=$INSTANCE
# Random database password:
DBPASS=`LC_CTYPE=C tr -dc "[:alnum:]" < /dev/urandom | head -c 16`
# Random omero root password:
OMEROPASS=`LC_CTYPE=C tr -dc "[:alnum:]" < /dev/urandom | head -c 16`

DATADIR="/repositories/$INSTANCE"

eval USERHOME=~$USERNAME
# Needs to be readable by nginx
chmod a+rx $USERHOME
OMERO_PREFIX="$USERHOME/OMERO-CURRENT"

echo "Installing server to $USERHOME"
cp "$SERVERZIP" "$USERHOME"
if [ -n "$OMEROSQL" ]; then
    cp "$OMEROSQL" "$USERHOME"
    OMEROSQL="`basename "$OMEROSQL"`"
fi

pushd "$USERHOME"

cat <<EOF >> "$CREDENTIALS"
instance: $INSTANCE
system user: $USERNAME
postgres user: $DBUSER
postgres password: $DBPASS
postgres database: $DBNAME
omero root password: $OMEROPASS
EOF


sudo -u "$USERNAME" unzip "$SERVERZIP"
sudo -u "$USERNAME" ln -s "${SERVERZIP%.zip}" "$OMERO_PREFIX"

echo "Creating database"
# Create a database user (createuser doesn't allow non-interactive password)
su - postgres -c \
    "psql -c \"CREATE ROLE \\\"$DBUSER\\\" WITH LOGIN ENCRYPTED PASSWORD '$DBPASS';\""
sudo -u postgres createdb -E UTF8 -O "$DBUSER" "$DBNAME"

OMERO="$OMERO_PREFIX/bin/omero"

echo "Creating data repository"
mkdir -p "$DATADIR"
chown "$USERNAME" "$DATADIR"
sudo -u "$USERNAME" "$OMERO" config set omero.data.dir "$DATADIR"

echo "Configuring OMERO database"
sudo -u "$USERNAME" "$OMERO" config set omero.db.name "$DBNAME"
sudo -u "$USERNAME" "$OMERO" config set omero.db.user "$DBUSER"
sudo -u "$USERNAME" "$OMERO" config set omero.db.pass "$DBPASS"

# Setup the database:
if [ -z "$OMEROSQL" ]; then
    OMEROSQL="$OMERO_PREFIX/db.sql"
    sudo -u "$USERNAME" "$OMERO" db script -f "$OMEROSQL" "" "" "$OMEROPASS"
fi

sudo -u "$USERNAME" \
    PGPASSWORD="$DBPASS" psql -hlocalhost -U"$DBUSER" "$DBNAME" -f "$OMEROSQL"

echo "Increasing Java heap size"
sudo -u "$USERNAME" sed -i.bak -e 's/Xmx512M/Xmx2048M/' \
    "$OMERO_PREFIX/etc/grid/templates.xml"

echo "Configuring OMERO web"
if [ -f /etc/nginx/conf.d/default.conf ]; then
    mv /etc/nginx/conf.d/default.conf /etc/nginx/conf.d/default.disabled
fi

# Modify nginx.conf to serve OMERO.web from a subdirectory
# TODO: Automatically set a unique fastcgi port for each instance
# TODO: At present you'll need to manually merge multiple instances
# into a single server block.
INSTANCE_FCPORT=4080
sudo -u "$USERNAME" "$OMERO" web config --system nginx --http 80 > \
    "/etc/nginx/conf.d/$INSTANCE.conf"
sed -i.bak \
    -e "s/location \//location \/$INSTANCE\//" \
    -e "s/fastcgi_pass 0.0.0.0:4080;/fastcgi_pass 0.0.0.0:$INSTANCE_FCPORT;/" \
    -e "s/fastcgi_param PATH_INFO \$fastcgi_script_name;/\\
            fastcgi_split_path_info ^(\/$INSTANCE)(.*)\$;\\
            fastcgi_param PATH_INFO \$fastcgi_path_info;\\
            fastcgi_param SCRIPT_NAME \$fastcgi_script_name;/" \
    -e 's/# fastcgi_param HTTPS $https;/fastcgi_param HTTPS $https;/' \
    "/etc/nginx/conf.d/$INSTANCE.conf"

sed -i.bak \
    -e '/"omero.web.static_url"/i \
    "omero.web.force_script_name": ["FORCE_SCRIPT_NAME", None, leave_none_unset],' \
    "$OMERO_PREFIX/lib/python/omeroweb/settings.py"

sudo -u "$USERNAME" "$OMERO" config set omero.web.static_url \
    "/$INSTANCE/static/"
sudo -u "$USERNAME" "$OMERO" config set omero.web.force_script_name \
    "/$INSTANCE"

service nginx restart

echo
echo "*** Credentials ($CREDENTIALS) ***"
cat "$CREDENTIALS"
echo "*** omero config ***"
sudo -u "$USERNAME" "$OMERO" config get

popd

echo "** Finished ***"
