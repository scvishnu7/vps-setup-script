#!/bin/bash


# ------------ config -----------------
# setup
doSetup=true
doWebServer=true
doVnc=false

# set email for logwatch (leave empty if you don't want logwatch)
#email=""

# make secure via and fail2ban and ufw
makeSecure=true

#hostname
read -rp "Enter the hostname of the server:" hostname
echo "$hostname" > /etc/hostname
echo "127.0.0.1 $hostname" >> /etc/hosts


# user
read -rp "Enter the username of the new user account:" username

promptForPassword

# public key for putting into .ssh/authorized_keys
# "ssh-rsa AAAAB3NzaC1................"
read -rp "Enter the public key of the new user account:" pubkey


# mariadb root password
# mariadbPassword="z"

# download path (via wget)
# ensure / at end
# downloadPath="https://raw.githubusercontent.com/amnah/vps-setup-script/master/"
downloadPath="https://raw.githubusercontent.com/scvishnu7/vps-setup-script/master"
# ------------ end config -----------------

# ------------ Helper Functions -----------
function promptForPassword() {
   PASSWORDS_MATCH=0
   while [ "${PASSWORDS_MATCH}" -eq "0" ]; do
       read -s -rp "Enter new UNIX password:" password
       printf "\n"
       read -s -rp "Retype new UNIX password:" password_confirmation
       printf "\n"

       if [[ "${password}" != "${password_confirmation}" ]]; then
           echo "Passwords do not match! Please try again."
       else
           PASSWORDS_MATCH=1
       fi
   done 
}
# ----------------------------------------


if $doSetup ; then
    # fix resolv.conf if you need to
    #echo -e "nameserver 8.8.8.8\nnameserver 4.2.2.2" > /etc/resolv.conf

    # update and upgrade
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get -y upgrade

    # nano + other apps for add-apt-repository cmd
    # http://stackoverflow.com/a/16032073 - page deleted :(
    apt-get -y install software-properties-common

    # update time
    #rm -f /etc/localtime
    #ln -s /usr/share/zoneinfo/America/New_York /etc/localtime
    # apt-get -y install ntp
    # service ntp restart

    # set up .bashrc for root (for sudo -i)
    echo -e "\n alias gst=\"git status\"\n alias du=\"du -h --max-depth=1\f" \n" >>~/.bashrc.bak
    
    #mv ~/.bashrc ~/.bashrc.bak
    #wget ${downloadPath}files/.bashrc -O ~/.bashrc
    #chmod 644 ~/.bashrc

    # prevent root login
    sed -i "s/PermitRootLogin yes/#PermitRootLogin yes/g" /etc/ssh/sshd_config
    echo -e "\n\nPermitRootLogin no\nPasswordAuthentication yes\n" >> /etc/ssh/sshd_config

    # create user and set up .bashrc + ssh
    adduser --disabled-password --gecos "" $username
    echo $username:$password | /usr/sbin/chpasswd
    adduser $username sudo
    mv /home/$username/.bashrc /home/$username/.bashrc.bak
    cp ~/.bashrc /home/$username/.bashrc
    mkdir /home/$username/.ssh
    echo "$pubkey" > /home/$username/.ssh/authorized_keys
    chmod 700 /home/$username/.ssh
    chmod 600 /home/$username/.ssh/authorized_keys
    chown -R $username.$username /home/$username
    service ssh restart

    # logwatch
    if [ -n "$email" ]; then
        apt-get -y install logwatch
        sed -i "s/--output mail/--output mail --mailto $email --detail high/g" /etc/cron.daily/00logwatch
    fi

    # empty out mail file
    cat /dev/null > /var/mail/root
fi

if $doWebServer ; then
    # install git nginx php mariadb
    export LANG=C.UTF-8
    add-apt-repository -y ppa:nginx/mainline
    add-apt-repository -y ppa:git-core/ppa
    add-apt-repository -y ppa:ondrej/php
    add-apt-repository -y ppa:chris-lea/redis-server
    sudo apt-key adv --fetch-keys 'https://mariadb.org/mariadb_release_signing_key.asc'
    sudo add-apt-repository 'deb [arch=amd64,arm64,ppc64el] https://mirrors.xtom.com.hk/mariadb/repo/10.6/ubuntu focal main'
    apt-get update
    apt-get -y purge apache2* libapache2* php5-*
    apt-get -y install lbzip2 unzip htop git redis-server curl nginx mcrypt memcached
    apt-get -y install php php-cli php-fpm php-mysql php-curl php-dev php-gd php-mbstring php-memcached php-xml php-intl
    DEBIAN_FRONTEND=noninteractive apt-get -y install mariadb-server mariadb-client
    # mysqladmin -u root password $mariadbPassword

    # install mongo
    # https://github.com/mongodb/mongo-php-driver/issues/138#issuecomment-184749966
    # NOTE: don't think this is needed anymore. can probably just do apt-get install php7.1-mongo
    #apt-get -y install autoconf g++ make openssl libssl-dev libcurl4-openssl-dev libcurl4-openssl-dev pkg-config libsasl2-dev libpcre3-dev
    #pecl install mongodb
    #echo -e "\nextension=mongodb.so\n" >> /etc/php/7.1/cli/php.ini
    #echo -e "\nextension=mongodb.so\n" >> /etc/php/7.1/fpm/php.ini

    # set up nginx
    # mv /etc/nginx/nginx.conf /etc/nginx/nginx.conf.bak
    # mv /etc/nginx/sites-available/default /etc/nginx/sites-available/default.bak
    # wget ${downloadPath}files/sites-available/default -O /etc/nginx/sites-available/default
    # wget ${downloadPath}files/sites-available/_common -O /etc/nginx/sites-available/_common
    # wget ${downloadPath}files/nginx.conf -O /etc/nginx/nginx.conf

    # set up data dir with symlinks to important directories
    mkdir -p /root/sites
    mkdir -p /var/www
    ln -s /var/www /root/sites
    ln -s /etc/nginx/nginx.conf /root/sites
    ln -s /etc/nginx/sites-available /root/sites
    ln -s /etc/nginx/sites-enabled /root/sites
    ln -s /var/log/nginx /root/sites/log

    # set up nginx logs and logrotate
    mkdir /var/log/nginx/_
    sed -i "s/*.log/*.log \/var\/log\/nginx\/*\/*.log/g" /etc/logrotate.d/nginx # add log files in subdirectories

    # add nginx configurations for fail2ban
    if $makeSecure ; then
        apt-get -y install fail2ban
        cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
        sed -i "s/\[nginx-http-auth\]/\[nginx-http-auth\]\nenabled = true/g" /etc/fail2ban/jail.local
        sed -i "s/\[nginx-botsearch\]/\[nginx-botsearch\]\nenabled = true/g" /etc/fail2ban/jail.local
        echo "\[sshd\]\n enabled = true\n port    = ssh\n maxretry = 3\n findtime = 600\n bantime  = 86400" >> /etc/fail2ban/jail.local
        sed -i "s/nginx\//nginx\/*\//g" /etc/fail2ban/paths-common.conf
        service fail2ban restart

        ufw allow openssh
        ufw allow 'nginx full'
        ufw enable
    fi

    # restart nginx services
    service php8.0-fpm restart
    service nginx restart

    # change owner and permissions
    chown -R www-data.www-data /var/www
    adduser $username www-data    # add user to www-data group
    adduser $username adm         # add user to adm group (for accessing /var/log)
    find /var/www -type d -print0 | xargs -0 chmod 0775
    #find /var/www -type f -print0 | xargs -0 chmod 0664 # not needed because there are no files in there

    # download backup and site scripts
    # wget ${downloadPath}backup.sh  
    # wget ${downloadPath}startNode.sh -O /home/$username/startNode.sh
    # chmod 700 backup.sh

    # display success message
    echo -e "------------------------------------------"
    echo -e "Done - You can now log into your '$username' account \n"
fi

if $doVnc ; then
    # install tightvnc and xfce
    apt-get -y install tightvncserver xfce4 xfce4-goodies

    # update scripts
    mkdir ~/.vnc
    wget ${downloadPath}files/xstartup  -O ~/.vnc/xstartup
    sed -i "s/#alias vnc/alias vnc/g" ~/.bashrc

    # display message about vnc
    echo -e "------------------------------------------"
    echo -e "Set up a vnc password:\n"
    echo -e "   echo 'password' | vncpasswd -f > ~/.vnc/passwd"
fi

# chmod this script so it can't run again
chmod 400 setup.sh

# display finished message
echo -e "------------------------------------------"
echo -e "setup.sh finished"
echo -e "------------------------------------------"
