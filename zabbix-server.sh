#!/bin/bash

#ditect OS and distribution
source /etc/os-release
case $PRETTY_NAME in
    "AlmaLinux"*)
        REPO_URL="https://repo.zabbix.com/zabbix/6.4/rhel/9/x86_64/zabbix-release-6.4-1.el9.noarch.rpm"
        pkg_uri=""
        pkg_mgr="dnf"
        os_type="rhel"
        ;;
#    "CentOS"*)
#        REPO_URL="https://repo.zabbix.com/zabbix/6.4/rhel/9/x86_64/zabbix-release-6.4-1.el9.noarch.rpm"
#        pkg_uri=""
#        pkg_mgr="dnf"
#        os_type="rhel"
#        ;;
    "Ubuntu 20.04"*)
        REPO_URL="https://repo.zabbix.com/zabbix/6.4/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.4-1+ubuntu20.04_all.deb"
        pkg_uri="zabbix-release_6.4-1+ubuntu20.04_all.deb"
        pkg_mgr="apt"
        os_type=deb
        ;;
    "Ubuntu 22.04"*)
        REPO_URL="https://repo.zabbix.com/zabbix/6.4/ubuntu/pool/main/z/zabbix-release/zabbix-release_6.4-1+ubuntu22.04_all.deb"
        pkg_uri="zabbix-release_6.4-1+ubuntu22.04_all.deb"
        pkg_mgr="apt"
        os_type="deb"
        ;;
    *)
        echo "sorry! this script not sopurt your OS yet"
        exit 0
        ;;
esac
#ask hostname and timezone
echo "select your zabbix hostname: "
read hostname
echo -n "enter your zabbix timezone(or press Enter for Asia/Tehran): "
read  timezone
default_h="example.com"
if [ -z "$hostname" ]; then
    timezone=$default_h
fi
default_t="Asia/Tehran"
if [ -z "$timezone" ]; then
    timezone=$default_t
fi
#set hostname and timezone
hostnamectl set-hostname $hostname
timedatectl set-timezone $timezone
#ask and set nameservers
echo -n "enter your dns server ip(or press Enter for default) : "
read  dns_server
default_d="8.8.8.8"
if [ -z "$dns_server" ]; then
    dns_server=$default_d
fi
echo -n "enter your secend dns server ip(or press Enter for default): "
read  dns_server2
default_d="4.2.2.4"
if [ -z "$dns_server2" ]; then
    dns_server2=$default_d
fi

resolv="/etc/resolv.conf"
if [ -f "$resolv" ]; then
else
    sudo touch /etc/resolv.conf
    echo -e "nameserver $dns_server\nnameserver $dns_server2"
fi 
sudo $pkg_mgr update -y
#you can sellect database and web server on next commit
#ask web server
#echo -e "select your web server between apache and nginx \na for apache and n for nginx : "
#read webserver

#ask database
#echo -e "select your web server between apache and nginx \nm for mariadb and p for postgresql : "
#read database

#almalinux installation
if [[ $os_type == "rhel" ]];then
    sudo $pkg_mgr install epel-relase -y
    sudo echo excludepkgs=zabbix* >> /etc/yum.repos.d/epel.repo
    sudo rpm -Uvh $REPO_URL
    sudo $pkg_mgr clean all
    sudo $pkg_mgr install zabbix-server-mysql zabbix-web-mysql zabbix-nginx-conf zabbix-sql-scripts zabbix-selinux-policy zabbix-agent langpacks-en glibc-all-langpacks mariadb-srver -y
    service_name="mariadb"
    systemctl enable $service_name
    if systemctl is-active --quiet "$service_name" ; then
        echo "$service_name running"
        else
            systemctl start "$service_name"
        fi
    mariadb-secure-installation
#create database and user
    echo "enter your data base password: "
    read -s db_pass
    mariadb -uroot -p <<EOF
create database zabbix_proxy character set utf8mb4 collate utf8mb4_bin;
create user zabbix@localhost identified by '$db_pass';
grant all privileges on zabbix.* to zabbix@localhost;
set global log_bin_trust_function_creators = 1;
EOF
#import data in database
    zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -uzabbix -p$db_pass zabbix
    log_bin_trust_function_creators
    mysql -uroot -p <<EOF
set global log_bin_trust_function_creators = 0;
EOF
    sed -i "s/# DBPassword=/DBPassword=$db_pass/" /etc/zabbix/zabbix_server.conf
    sed -i 's/#        listen          8080;/         listen          8080;/' /etc/zabbix/nginx.conf
    sed -i "s/#        server_name     example.com;/        server_name     $hostname;/" /etc/zabbix/nginx.conf
    sudo systemctl restart zabbix-server zabbix-agent nginx php-fpm
    sudo systemctl enable zabbix-server zabbix-agent nginx php-fpm
#Ubuntu installation
     
elif [[ $os_type == "deb" ]];then
    wget $REPO_URL
    sudo dpkg -i $pkg_uri
    sudo $pkg_mgr update -y
    sudo $pkg_mgr install zabbix-server-mysql zabbix-frontend-php zabbix-nginx-conf zabbix-sql-scripts zabbix-agent -y
    sudo $pkg_mgr install software-properties-common -y
    curl -LsS -O https://downloads.mariadb.com/MariaDB/mariadb_repo_setup
    bash mariadb_repo_setup --mariadb-server-version=10.6
    sudo $pkg_mgr update -y
    sudo $pkg_mgr install mariadb-server-10.6 mariadb-client-10.6 -y
    sudo systemctl start mariadb
    sudo systemctl enable mariadb
    echo "enter your data base password: "
    read -s db_pass
    sudo mysql -u root -p <<EOF
create database zabbix character set utf8mb4 collate utf8mb4_bin;
create user zabbix@localhost identified by '$db_pass';
grant all privileges on zabbix.* to zabbix@localhost;
set global log_bin_trust_function_creators = 1;
EOF
    zcat /usr/share/zabbix-sql-scripts/mysql/server.sql.gz | mysql --default-character-set=utf8mb4 -uzabbix -p$db_pass zabbix
    sudo mysql -u root -p <<EOF
set global log_bin_trust_function_creators = 0;
EOF
    sed -i "s/# DBPassword=/DBPassword=$db_pass/" /etc/zabbix/zabbix_server.conf
    sed -i 's/#        listen          8080;/         listen          8080;/' /etc/zabbix/nginx.conf
    sed -i "s/#        server_name     example.com;/        server_name     example.com;/" /etc/zabbix/nginx.conf
    sudo systemctl restart zabbix-server zabbix-agent nginx php7.4-fpm
    sudo systemctl enable zabbix-server zabbix-agent nginx php7.4-fpm
    service_name="zabbix-server"
    if systemctl is-active --quiet "$service_name.service" ; then
        echo "$service_name running"
    else
        systemctl start "$service_name"
    fi
echo "zabbix service installed "
fi
