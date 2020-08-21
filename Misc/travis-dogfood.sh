#!/bin/bash

set -ex
tests=$1

SERVER=$(hostname -f)

function generate_rsync_cfg() {
  LOGS="/var/www/html/beaker-logs"
  mkdir -p $LOGS
  chown nobody $LOGS
  chmod 755 $LOGS
  cat <<__EOF__ > /etc/rsyncd.conf
use chroot = false

[beaker-logs]
    path = $LOGS
    comment = beaker logs
    read_only = false
__EOF__
}

function generate_lc_cfg() {
    cat <<__EOF__ > /etc/beaker/labcontroller.conf
HUB_URL = "http://$SERVER/bkr/"
AUTH_METHOD = "password"
USERNAME = "host/$SERVER"
PASSWORD = "testing"
CACHE = True
ARCHIVE_SERVER = "http://$SERVER/beaker-logs"
ARCHIVE_BASEPATH = "/var/www/html/beaker"
ARCHIVE_RSYNC = "rsync://$SERVER/beaker-logs"
RSYNC_FLAGS = "-arv --timeout 300"
__EOF__
}

function generate_client_cfg() {
  cat <<__EOF__ >/etc/beaker/client.conf
HUB_URL = "http://$SERVER/bkr"
AUTH_METHOD = "password"
USERNAME = "admin"
PASSWORD = "testing"
__EOF__
}

function init() {
    echo "Setup Beaker config folder ..."
    mkdir -p "/etc/beaker"
    chmod 755 "/etc/beaker"
}

function client()
{
    echo "Configure Beaker client"
    cat <<__EOF__ >/etc/beaker/client.conf
HUB_URL = "http://$SERVER/bkr"
AUTH_METHOD = "password"
USERNAME = "admin"
PASSWORD = "testing"
__EOF__
}

function inventory()
{
  yum install -y rh-mariadb102-mariadb-server rh-mariadb102-mariadb-syspaths MySQL-python
  cat >/etc/opt/rh/rh-mariadb102/my.cnf.d/beaker.cnf <<EOF
[mysqld]
max_allowed_packet=50M
character_set_server=utf8
$MYSQL_EXTRA_CONFIG
EOF
  systemctl start rh-mariadb102-mariadb
  mysql -u root -e "CREATE DATABASE beaker;"
  mysql -u root -e "GRANT ALL ON beaker.* TO beaker@localhost IDENTIFIED BY 'beaker';"

  echo "Install Beaker server"
  yum install -y beaker-server$VERSION
  echo "Installed $(rpm -q beaker-server)"
  if [[ -n "$EXPECT_BEAKER_GIT_BUILD" && "$(rpm -q beaker-server)" != *.git.* ]] ; then
        echo "Git build was not installed (hint: does destination branch contain latest tags?)"
        exit 1
  fi

  echo "Configure Beaker server"
  mkdir -p /var/www/beaker/harness
cat << __EOF__ > /etc/beaker/motd.txt
<span>Integration tests are running against this server</span>
__EOF__
  echo "Initialize database"
  beaker-init -u admin -p testing -e root@localhost.com

#  echo "Configure firewall"
#  systemctl stop firewalld

  echo "Start services"
  systemctl start httpd
  systemctl start beakerd

  echo "Add lab controllers"
  curl -f -s -o /dev/null -c cookie -d user_name=admin -d password=testing -d login1 http://$SERVER/bkr/login
  curl -f -s -o /dev/null -b cookie -d fqdn=$SERVER -d lusername=host/$SERVER -d lpassword=testing -d email=root@$SERVER.com http://$SERVER/bkr/labcontrollers/save

  echo "Enable rsync for fake archive server"
  generate_rsync_cfg
  systemctl enable rsyncd
}

function labcontroller()
{
    echo "Install Beaker lab controller"
    yum install -y beaker-lab-controller$VERSION beaker-lab-controller-addDistro$VERSION
    echo "Installed $(rpm -q beaker-lab-controller)"
    if [[ -n "$EXPECT_BEAKER_GIT_BUILD" && "$(rpm -q beaker-lab-controller)" != *.git.* ]] ; then
        echo "Git build was not installed (hint: does destination branch contain latest tags?)"
        exit 1
    fi

    echo "Configure Beaker lab controller"
    # Configure beaker-proxy config
    generate_lc_cfg

#    echo "Configure firewall"
#    systemctl stop firewalld

    echo "Start TFTP service"
    yum install -y tftp-server
    systemctl enable tftp.socket
    systemctl start tftp.socket

    # There is beaker-transfer as well but it's disabled by default
    for service in httpd beaker-proxy beaker-watchdog beaker-provision ; do
        systemctl enable $service
        systemctl start $service
    done

    if [ -n "$ENABLE_BEAKER_PXEMENU" ] ; then
        echo "Enable PXE menu"
        cat >/etc/cron.hourly/beaker_pxemenu <<"EOF"
#!/bin/bash
exec beaker-pxemenu -q
EOF
        chmod 755 /etc/cron.hourly/beaker_pxemenu
    fi

    echo "Configuring apache for WebDav DELETE"
    mkdir /var/www/auth
    local user=log-delete realm="$(hostname -f)" password=password
    echo "$user:$realm:$(echo -n "$user:$realm:$password" | md5sum - | cut -d' ' -f1)" >/var/www/auth/.digest_pw
    echo "Contents of digest password file: $(cat /var/www/auth/.digest_pw)"
    echo "Adding DAV configuration to apache conf"
    cat >/etc/httpd/conf.d/beaker-log-delete.conf <<EOF
<DirectoryMatch "/var/www/(beaker/logs|html/beaker\-logs)">
        Options Indexes Multiviews
        Order allow,deny
        Allow from all

        <LimitExcept GET HEAD>
                Dav On
                AuthType Digest
                AuthDigestDomain /var/www/beaker/logs/
                AuthDigestProvider file
                AuthUserFile /var/www/auth/.digest_pw
                Require user log-delete
                AuthName "$(hostname -f)"
        </LimitExcept>
</DirectoryMatch>
EOF
    echo  "Wrote WebDav DELETE config for Beaker lab controller" $?
    echo "Restarting Apache"
    systemctl restart httpd
}


# Debug info first
getenforce
id -Z
nproc
pwd

setenforce 0

yum install -y \
  centos-release-scl \
  epel-release

(cd /etc/yum.repos.d/ && curl -L -O -f https://beaker-project.org/yum/beaker-server-RedHatEnterpriseLinux.repo)

init
client
inventory
labcontroller

systemctl stop beakerd
yum install -y beaker-integration-tests$VERSION
rpm -e --nodeps firefox
yum install -y http://vault.centos.org/7.5.1804/updates/x86_64/Packages/firefox-52.7.3-1.el7.centos.x86_64.rpm
mysql -u root -e "CREATE DATABASE beaker_migration_test; GRANT ALL ON beaker_migration_test.* TO beaker@localhost;"
# Updates the Beaker config to match what the tests are expecting.

if [ -e /etc/beaker/server.cfg ] ; then
    sed --regexp-extended --in-place=-orig --copy -e '
        /^#?beaker\.log_delete_user/c       beaker.log_delete_user = "log-delete"
        /^#?beaker\.log_delete_password/c   beaker.log_delete_password = "password"
        /^#?mail\.on/c                      mail.on = True
        /^#?mail\.smtp\.server/c            mail.smtp.server = "127.0.0.1:19999"
        /^#?beaker\.reliable_distro_tag/c   beaker.reliable_distro_tag = "RELEASED"
        /^#?beaker\.max_running_commands /c beaker.max_running_commands = 10
        /^#?beaker\.kernel_options /c       beaker.kernel_options = "noverifyssl"
        /^#?identity\.ldap\.enabled/c       identity.ldap.enabled = True
        /^#?identity\.soldapprovider\.uri/c identity.soldapprovider.uri = "ldap://localhost:3899/"
        /^#?identity\.soldapprovider\.basedn/c identity.soldapprovider.basedn = "dc=example,dc=invalid"
        /^#?identity\.soldapprovider\.autocreate/c identity.soldapprovider.autocreate = True
        /\[global\]/a                       beaker.migration_test_dburi = "mysql://beaker:beaker@localhost/beaker_migration_test?charset=utf8"
        ' /etc/beaker/server.cfg
    service httpd reload
fi

if [ -e /etc/beaker/labcontroller.conf ] ; then
    sed --regexp-extended --in-place=-orig --copy -e '
        $a SLEEP_TIME = 5
        $a POWER_ATTEMPTS = 2
        ' /etc/beaker/labcontroller.conf
    # Added in Beaker 26.0+
    watchdog_script=$(echo /usr/lib/python2.*/site-packages/bkr/inttest/labcontroller/watchdog-script-test.sh)
    if [ -e "$watchdog_script" ] ; then
        sed --regexp-extended --in-place -e "
            \$a WATCHDOG_SCRIPT = \"$watchdog_script\"
            " /etc/beaker/labcontroller.conf
    fi
    service beaker-proxy condrestart
    service beaker-provision condrestart
    service beaker-watchdog condrestart
    service beaker-transfer condrestart
fi

if [ -e /etc/cron.d/beaker ] ; then
    # Comment out beaker-refresh-ldap cron job, since it won't do anything most
    # of the time, but it can interfere with tests which are invoking
    # beaker-refresh-ldap directly.
    sed --in-place=-orig --copy -e '
        /beaker-refresh-ldap/ s/^/#/
        ' /etc/cron.d/beaker
fi
export BEAKER_LABCONTROLLER_HOSTNAME="$(hostname -f)"
export BEAKER_SERVER_BASE_URL="http://$(hostname -f)/bkr/"
export BEAKER_CLIENT_COMMAND=bkr
export export BEAKER_WIZARD_COMMAND="beaker-wizard"

# Let's use edited config
export BEAKER_CONFIG_FILE="/etc/beaker/server.cfg"
export BEAKER_CLIENT_CONF="/etc/beaker/client.conf"
export BEAKER_LABCONTROLLER_CONFIG_FILE="/etc/beaker/labcontroller.conf"

python -c '__requires__ = ["CherryPy < 3.0"]; import pkg_resources; from nose.core import main; main()' \
-v --logging-format='%(asctime)s %(name)s %(levelname)s %(message)s' \
$tests
