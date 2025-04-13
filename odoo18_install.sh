#!/bin/bash
#################################################################################################
# ODOO INSTALLER SCRIPT (GENERIC) - Ready for GitHub / Reuse
# Author: Tu Nombre
# Version: Odoo 18.0 (Compatible con EE y CE)
# -----------------------------------------------------------------------------------------------
# Este script instala Odoo con PostgreSQL, NGINX (opcional), Certbot (opcional) y Wkhtmltopdf.
# Está preparado para que se pueda reutilizar como base para instalaciones personalizadas.
#################################################################################################

# ==============================================================================================
# CONFIGURACIÓN GENERAL
# ==============================================================================================

OE_USER="odoo"
OE_HOME="/$OE_USER"
OE_HOME_EXT="/$OE_USER/${OE_USER}-server"

OE_PORT="8069"
LONGPOLLING_PORT="8072"
OE_VERSION="18.0"

IS_ENTERPRISE="False"
INSTALL_POSTGRESQL_FOURTEEN="False"
INSTALL_NGINX="True"
ENABLE_SSL="True"

OE_SUPERADMIN="contrasena"
GENERATE_RANDOM_PASSWORD="False"
OE_CONFIG="${OE_USER}-server"

WEBSITE_NAMES=("empresa1.com" "empresa2.com")
ADMIN_EMAIL="admin@odoo.com"

# CREDENCIALES DE GITHUB ENTERPRISE
GITHUB_USER="gh-user"
GITHUB_TOKEN="token"


# ==============================================================================================
# OPTIMIZACIÓN DEL SISTEMA (OPCIONAL)
# ==============================================================================================

echo -e "\n---- Supressing service restart prompts ----"
sudo sed -i 's/#$nrconf{restart} = '"'"'i'"'"';/$nrconf{restart} = '"'"'a'"'"';/g' /etc/needrestart/needrestart.conf
sudo sed -i "s/#\$nrconf{kernelhints} = -1;/\$nrconf{kernelhints} = -1;/g" /etc/needrestart/needrestart.conf

# ==============================================================================================
# ACTUALIZACIÓN DEL SISTEMA
# ==============================================================================================

echo -e "\n---- Updating system ----"
sudo apt-get update -y
sudo apt-get upgrade -y
sudo apt-get install libpq-dev -y

# ==============================================================================================
# INSTALACIÓN DE POSTGRESQL
# ==============================================================================================

echo -e "\n---- Installing PostgreSQL ----"
if [ $INSTALL_POSTGRESQL_FOURTEEN = "True" ]; then
    echo -e "\n---- Installing PostgreSQL v14 ----"
    sudo curl -fsSL https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg
    sudo sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
    sudo apt-get update -y
    sudo apt-get install postgresql-16 -y
else
    echo -e "\n---- Installing default PostgreSQL ----"
    sudo apt-get install postgresql postgresql-server-dev-all -y
fi

echo -e "\n---- Creating PostgreSQL user for Odoo ----"
sudo su - postgres -c "createuser -s $OE_USER" 2> /dev/null || true

# ==============================================================================================
# DEPENDENCIAS DEL SISTEMA Y PYTHON
# ==============================================================================================

echo -e "\n---- Installing system dependencies ----"
sudo apt-get install python3 python3-pip -y
sudo apt-get install git python3-cffi build-essential wget python3-dev python3-venv python3-wheel libxslt-dev libzip-dev libldap2-dev libsasl2-dev python3-setuptools node-less libpng-dev libjpeg-dev gdebi -y

echo -e "\n---- Installing Python packages ----"
sudo -H pip3 install -r https://github.com/odoo/odoo/raw/${OE_VERSION}/requirements.txt --break-system-packages

echo -e "\n---- Installing Node.js and rtlcss ----"
sudo apt-get install nodejs npm -y
sudo npm install -g rtlcss

# ==============================================================================================
# USUARIO DEL SISTEMA
# ==============================================================================================

echo -e "\n---- Creating system user for Odoo ----"
sudo adduser --system --quiet --shell=/bin/bash --home=$OE_HOME --gecos 'ODOO' --group $OE_USER
sudo adduser $OE_USER sudo

echo -e "\n---- Creating log directory ----"
sudo mkdir /var/log/$OE_USER
sudo chown $OE_USER:$OE_USER /var/log/$OE_USER

# ==============================================================================================
# INSTALACIÓN DE ODOO (CE o EE)
# ==============================================================================================

echo -e "\n==== Installing Odoo $OE_VERSION ===="
sudo git clone --depth 1 --branch $OE_VERSION https://www.github.com/odoo/odoo $OE_HOME_EXT/

if [ $IS_ENTERPRISE = "True" ]; then
    sudo pip3 install psycopg2-binary pdfminer.six --break-system-packages
    sudo ln -s /usr/bin/nodejs /usr/bin/node
    sudo su $OE_USER -c "mkdir -p $OE_HOME/enterprise/addons"

    GITHUB_RESPONSE=$(sudo git clone --depth 1 --branch $OE_VERSION https://$GITHUB_USER:$GITHUB_TOKEN@github.com/odoo/enterprise.git "$OE_HOME/enterprise/addons" 2>&1)

    if [[ $GITHUB_RESPONSE == *"Authentication"* || $GITHUB_RESPONSE == *"Permission denied"* ]]; then
        echo "ERROR: Failed to authenticate with GitHub Enterprise repo."
        exit 1
    elif [[ $GITHUB_RESPONSE == *"fatal"* || $GITHUB_RESPONSE == *"error"* ]]; then
        echo "ERROR: Failed to clone Enterprise repo."
        exit 1
    else
        echo -e "\n---- Enterprise code added ----"
    fi

    echo -e "\n---- Installing additional Enterprise libraries ----"
    sudo -H pip3 install num2words ofxparse dbfread ebaysdk firebase_admin pyOpenSSL --break-system-packages
    sudo npm install -g less
    sudo npm install -g less-plugin-clean-css
fi

# ==============================================================================================
# DIRECTORIOS ADICIONALES Y CONFIG DE ODOO
# ==============================================================================================

echo -e "\n---- Creating custom addons folder ----"
sudo su $OE_USER -c "mkdir -p $OE_HOME/custom/addons"

echo -e "\n---- Setting permissions ----"
sudo chown -R $OE_USER:$OE_USER $OE_HOME/*

echo -e "\n---- Creating Odoo config file ----"
sudo touch /etc/${OE_CONFIG}.conf

if [ $GENERATE_RANDOM_PASSWORD = "True" ]; then
    OE_SUPERADMIN=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 16 | head -n 1)
fi

sudo bash -c "cat > /etc/${OE_CONFIG}.conf <<EOF
[options]
admin_passwd = $OE_SUPERADMIN
http_port = $OE_PORT
logfile = /var/log/${OE_USER}/${OE_CONFIG}.log
EOF"

if [ $IS_ENTERPRISE = "True" ]; then
    echo "addons_path=${OE_HOME}/enterprise/addons,${OE_HOME_EXT}/addons" | sudo tee -a /etc/${OE_CONFIG}.conf
else
    echo "addons_path=${OE_HOME_EXT}/addons,${OE_HOME}/custom/addons" | sudo tee -a /etc/${OE_CONFIG}.conf
fi

sudo chown $OE_USER:$OE_USER /etc/${OE_CONFIG}.conf
sudo chmod 640 /etc/${OE_CONFIG}.conf

# ==============================================================================================
# SCRIPT DE INICIO (start.sh)
# ==============================================================================================

echo -e "\n---- Creating start.sh script ----"
sudo bash -c "cat > $OE_HOME_EXT/start.sh <<EOF
#!/bin/sh
sudo -u $OE_USER $OE_HOME_EXT/odoo-bin --config=/etc/${OE_CONFIG}.conf
EOF"
sudo chmod 755 $OE_HOME_EXT/start.sh

# ==============================================================================================
# CREACIÓN DE SERVICIO COMO DAEMON (init.d)
# ==============================================================================================

echo -e "\n---- Creating init.d service file ----"
cat <<EOF > ~/$OE_CONFIG
#!/bin/sh
### BEGIN INIT INFO
# Provides: $OE_CONFIG
# Required-Start: \$remote_fs \$syslog
# Required-Stop: \$remote_fs \$syslog
# Should-Start: \$network
# Should-Stop: \$network
# Default-Start: 2 3 4 5
# Default-Stop: 0 1 6
# Short-Description: Odoo ERP Daemon
# Description: Enterprise Business Applications
### END INIT INFO

PATH=/sbin:/bin:/usr/sbin:/usr/bin:/usr/local/bin
DAEMON=$OE_HOME_EXT/odoo-bin
NAME=$OE_CONFIG
DESC=$OE_CONFIG
USER=$OE_USER
CONFIGFILE="/etc/${OE_CONFIG}.conf"
PIDFILE=/var/run/\${NAME}.pid
DAEMON_OPTS="-c \$CONFIGFILE"

[ -x \$DAEMON ] || exit 0
[ -f \$CONFIGFILE ] || exit 0

checkpid() {
  [ -f \$PIDFILE ] || return 1
  pid=\`cat \$PIDFILE\`
  [ -d /proc/\$pid ] && return 0
  return 1
}

case "\$1" in
  start)
    echo -n "Starting \$DESC: "
    start-stop-daemon --start --quiet --pidfile \$PIDFILE \
      --chuid \$USER --background --make-pidfile \
      --exec \$DAEMON -- \$DAEMON_OPTS
    echo "\$NAME."
    ;;
  stop)
    echo -n "Stopping \$DESC: "
    start-stop-daemon --stop --quiet --pidfile \$PIDFILE --oknodo
    echo "\$NAME."
    ;;
  restart|force-reload)
    echo -n "Restarting \$DESC: "
    start-stop-daemon --stop --quiet --pidfile \$PIDFILE --oknodo
    sleep 1
    start-stop-daemon --start --quiet --pidfile \$PIDFILE \
      --chuid \$USER --background --make-pidfile \
      --exec \$DAEMON -- \$DAEMON_OPTS
    echo "\$NAME."
    ;;
  *)
    echo "Usage: \$NAME {start|stop|restart|force-reload}" >&2
    exit 1
    ;;
esac
exit 0
EOF

sudo mv ~/$OE_CONFIG /etc/init.d/$OE_CONFIG
sudo chmod 755 /etc/init.d/$OE_CONFIG
sudo chown root: /etc/init.d/$OE_CONFIG
sudo update-rc.d $OE_CONFIG defaults

# ==============================================================================================
# NGINX CONFIGURATION (IF ENABLED)
# ==============================================================================================

if [ "$INSTALL_NGINX" = "True" ]; then
  echo -e "\n---- Installing and configuring NGINX ----"
  sudo apt install nginx -y

  for DOMAIN in "${WEBSITE_NAMES[@]}"; do
    cat <<EOF > ~/${DOMAIN}
server {
  listen 80;
  server_name $DOMAIN;

  proxy_set_header X-Forwarded-Host \$host;
  proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  proxy_set_header X-Forwarded-Proto \$scheme;
  proxy_set_header X-Real-IP \$remote_addr;
  add_header X-Frame-Options "SAMEORIGIN";
  add_header X-XSS-Protection "1; mode=block";
  proxy_set_header X-Client-IP \$remote_addr;
  proxy_set_header HTTP_X_FORWARDED_HOST \$remote_addr;

  access_log /var/log/nginx/${OE_USER}-${DOMAIN}-access.log;
  error_log  /var/log/nginx/${OE_USER}-${DOMAIN}-error.log;

  proxy_buffers 16 64k;
  proxy_buffer_size 128k;

  proxy_read_timeout 900s;
  proxy_connect_timeout 900s;
  proxy_send_timeout 900s;
  proxy_next_upstream error timeout invalid_header http_500 http_502 http_503;

  gzip on;
  gzip_min_length 1100;
  gzip_buffers 4 32k;
  gzip_types text/css text/less text/plain text/xml application/xml application/json application/javascript application/pdf image/jpeg image/png;
  gzip_vary on;

  client_header_buffer_size 4k;
  large_client_header_buffers 4 64k;
  client_max_body_size 0;

  location / {
    proxy_pass http://127.0.0.1:$OE_PORT;
    proxy_redirect off;
  }

  location /longpolling {
    proxy_pass http://127.0.0.1:$LONGPOLLING_PORT;
  }

  location ~* \.(js|css|png|jpg|jpeg|gif|ico)$ {
    expires 2d;
    proxy_pass http://127.0.0.1:$OE_PORT;
    add_header Cache-Control "public, no-transform";
  }

  location ~ /[a-zA-Z0-9_-]*/static/ {
    proxy_cache_valid 200 302 60m;
    proxy_cache_valid 404 1m;
    proxy_buffering on;
    expires 864000;
    proxy_pass http://127.0.0.1:$OE_PORT;
  }
}
EOF

    sudo mv ~/${DOMAIN} /etc/nginx/sites-available/${DOMAIN}
    sudo ln -s /etc/nginx/sites-available/${DOMAIN} /etc/nginx/sites-enabled/${DOMAIN}
  done

  sudo rm /etc/nginx/sites-enabled/default
  sudo service nginx reload
  echo "proxy_mode = True" | sudo tee -a /etc/${OE_CONFIG}.conf
fi

# ==============================================================================================
# SSL CONFIGURATION WITH CERTBOT (IF ENABLED)
# ==============================================================================================

if [ "$INSTALL_NGINX" = "True" ] && [ "$ENABLE_SSL" = "True" ] && [ "$ADMIN_EMAIL" != "odoo@example.com" ]; then
  echo -e "\n---- Installing SSL with Certbot ----"
  sudo apt-get update -y
  sudo snap install core; sudo snap refresh core
  sudo snap install --classic certbot
  sudo ln -s /snap/bin/certbot /usr/bin/certbot

  for DOMAIN in "${WEBSITE_NAMES[@]}"; do
    sudo certbot --nginx -d $DOMAIN --noninteractive --agree-tos --email $ADMIN_EMAIL --redirect
  done

  sudo service nginx reload
  echo "SSL/HTTPS is enabled!"
else
  echo "SSL/HTTPS NOT enabled — check ADMIN_EMAIL or WEBSITE_NAMES configuration."
fi

# ==============================================================================================
# WKHTMLTOPDF INSTALLATION (REQUIRED FOR REPORTS)
# ==============================================================================================

echo -e "\n---- Installing wkhtmltopdf ----"
sudo wget http://archive.ubuntu.com/ubuntu/pool/main/o/openssl/libssl1.1_1.1.1f-1ubuntu2_amd64.deb
sleep 5
sudo dpkg -i libssl1.1_1.1.1f-1ubuntu2_amd64.deb
sudo apt --fix-broken install -y

sudo wget https://github.com/wkhtmltopdf/wkhtmltopdf/releases/download/0.12.5/wkhtmltox_0.12.5-1.bionic_amd64.deb
sleep 5
sudo apt-get install -y xfonts-75dpi
sudo dpkg -i wkhtmltox_0.12.5-1.bionic_amd64.deb
sudo apt --fix-broken install -y

# ==============================================================================================
# POST-INSTALACIÓN Y REINICIO
# ==============================================================================================

echo -e "\n---- Starting Odoo service ----"
sudo service $OE_CONFIG restart

echo "-----------------------------------------------------------"
echo "Odoo $OE_VERSION installation complete!"
if [ "$INSTALL_NGINX" = "True" ]; then
  echo "Nginx config: /etc/nginx/sites-available/$WEBSITE_NAME"
fi
echo "-----------------------------------------------------------"

# Instalar librerías de impresión PDF
sudo apt-get install libfreetype6-dev liblcms2-dev libpng-dev -y
sudo pip install reportlab pillow rlPyCairo --break-system-packages

# Guardar ruta del script
SCRIPT_PATH=$(realpath "$0")

echo "Service will reboot in 5 seconds..."
(sleep 5 && sudo reboot) &
sudo rm -f "$SCRIPT_PATH"
