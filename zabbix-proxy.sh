#!/bin/bash

#ditect OS and distribution
source /etc/os-release
case $PRETTY_NAME in
#    "AlmaLinux"*)
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
#almalinux installation
if [[ $os_type == "rhel" ]];then
    sudo $pkg_mgr install epel-relase -y
    sudo rpm -Uvh $REPO_URL
#Ubuntu installation
     
elif [[ $os_type == "deb" ]];then
    wget $REPO_URL
    sudo dpkg -i $pkg_uri
    sudo $pkg_mgr update -y
    sudo $pkg_mgr install zabbix-proxy-mysql zabbix-sql-scripts -y
    sudo $pkg_mgr install software-properties-common -y
    curl -LsS -O https://downloads.mariadb.com/MariaDB/mariadb_repo_setup
    bash mariadb_repo_setup --mariadb-server-version=10.6
    $pkg_mgr update -y
    sudo $pkg_mgr -y install mariadb-common mariadb-server-10.6 mariadb-client-10.6 -y
    sudo systemctl start mariadb
    sudo systemctl enable mariadb
    sudo mysql -u root -p <<EOF
create database zabbix_proxy character set utf8mb4 collate utf8mb4_bin;
create user zabbix@localhost identified by 'password';
grant all privileges on zabbix_proxy.* to zabbix@localhost;
set global log_bin_trust_function_creators = 1;
EOF
    cat /usr/share/zabbix-sql-scripts/mysql/proxy.sql | mysql --default-character-set=utf8mb4 -uzabbix -ppassword zabbix_proxy
    sudo mysql -u root -p <<EOF
set global log_bin_trust_function_creators = 0;
EOF
    sed -i 's/Hostname=Zabbix proxy/Hostname=Zabbix-proxy/' /etc/zabbix/zabbix_proxy.conf
    sed -i 's/# LogFileSize=/LogFileSize=1/' /etc/zabbix/zabbix_proxy.conf
    sed -i 's/# DBPassword=/DBPassword=password/' /etc/zabbix/zabbix_proxy.conf
    sudo systemctl restart zabbix-proxy
    sudo systemctl enable zabbix-proxy
    service_name="zabbix-proxy"
    if systemctl is-active --quiet "$service_name.service" ; then
        echo "$service_name running"
    else
        systemctl start "$service_name"
    fi
fi
