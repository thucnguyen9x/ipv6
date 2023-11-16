#!/bin/sh
#SCRIPT BY PA43
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin

FIRST_PORT=10000
LAST_PORT=12000
MAXCONNECTION=$(( $LAST_PORT - $FIRST_PORT + 10 ))

WORKDATA=~/tube_data.txt

if iptables -S | grep -ce '-m state --state NEW -j ACCEPT'; then
    if  grep -q "3proxy" "/etc/rc.local" ; then
        echo "clear 3proxy in /etc/rc.local";
        sed -i '/iptables.sh/d' /etc/rc.local
        sed -i '/ifconfig.sh/d' /etc/rc.local
        sed -i '/ulimit -n/d' /etc/rc.local
        sed -i '/3proxy/d' /etc/rc.local
        sed -i '/echo /d' /etc/rc.local
        sed -i '/exit 0/d' /etc/rc.local
        sed -i '/set /d' /etc/rc.local
    fi
    echo "Reboot to clear ifconfig"
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -F
    iptables -X
    reboot
    exit 1
fi

pkill 3proxy
#systemctl stop firewalld

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':') && [[ -z "$IP6" ]] && echo "ERROR IPv6" && exit 1

rm -r ~/tube_*
rm -r ~/*.tar.gz
rm -rf ~/3proxy*

random() {
	tr </dev/urandom -dc A-Za-z0-9 | head -c5
	echo
}

array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
gen64() {
	ip64() {
		echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
	}
	echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}
install_3proxy() {
    echo "installing 3proxy"
    URL="https://github.com/3proxy/3proxy/archive/refs/tags/0.9.4.tar.gz"
    wget -qO- $URL | bsdtar -xvf-
    cd 3proxy-0.9.4
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp bin/* /usr/local/etc/3proxy/bin/
    cd ~
}

gen_3proxy() {
    cat <<EOF
daemon
maxconn ${MAXCONNECTION}
nserver 1.1.1.1
nserver 8.8.4.4
nserver 2001:4860:4860::8888
nserver 2001:4860:4860::8844
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
stacksize 6291456 
flush
auth strong

users pa43:CL:Pa43PA

$(awk -F "/" '{print "auth strong\n" \
"allow " $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${WORKDATA})
EOF
}

gen_proxy_file_for_user() {
    cat >~/tube_proxy.txt <<EOF
$(awk -F "/" '{print "http://" $1 ":" $2 "@" $3 ":" $4 }' ${WORKDATA})
EOF
}

gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "pa43/Pa43PA/$IP4/$port/$(gen64 $IP6)"
    done
}

gen_iptables() {
    cat <<EOF
set +e
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -P OUTPUT ACCEPT
iptables -F
iptables -X
$(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 " -m state --state NEW -j ACCEPT"}' ${WORKDATA}) 
set -e
EOF
}

gen_ifconfig() {
    cat <<EOF
set +e
$(awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA})
set -e
EOF
}
echo "Update OS"
yum update -y
echo "installing apps"
yum -y groupinstall "Development Tools"
yum -y install nano
yum -y install net-tools
yum -y install wget
yum -y install bsdtar
#yum install iptables-services -y
install_3proxy

cd ~

echo "Internal ip = ${IP4}. Exteranl sub for ip6 = ${IP6}"

gen_data >$WORKDATA
gen_iptables >~/tube_iptables.sh
gen_ifconfig >~/tube_ifconfig.sh

gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg

ulimit -n 1048576
sed -i '/nofile/d' /etc/security/limits.conf
sed -i '/kernel.threads-max/d' /etc/sysctl.conf
sed -i '/fs.file-max/d' /etc/sysctl.conf
sed -i '/UserTasksMax/d' /etc/systemd/system.conf

echo "* hard nofile 1048576" >> /etc/security/limits.conf
echo "* soft nofile 1048576" >> /etc/security/limits.conf
echo "root hard nofile 1048576" >> /etc/security/limits.conf
echo "root soft nofile 1048576" >> /etc/security/limits.conf
echo 120000 > /proc/sys/kernel/threads-max
sysctl -w kernel.threads-max=120000
sysctl -w kernel.threads-max=120000 >> /etc/sysctl.conf
sysctl -w fs.file-max=500000
sysctl -w fs.file-max=500000 >> /etc/sysctl.conf
echo 200000 > /proc/sys/kernel/pid_max
echo 600000 > /proc/sys/vm/max_map_count
echo "UserTasksMax=60000" >> /etc/systemd/system.conf
echo "net.ipv4.ip_local_port_range = 10000 65535" >> /etc/sysctl.d/net.ipv4.ip_local_port_range.conf

chmod +x tube_* /usr/local/etc/3proxy/bin/3proxy

~/tube_iptables.sh
sleep 7
~/tube_ifconfig.sh

/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
gen_proxy_file_for_user

echo "Wait 20s for proxy ready"
sleep 20

DEMOPROXY="http://pa43:Pa43PA@${IP4}:11700"
CHECKIP=$(curl -x "${DEMOPROXY}" --connect-timeout 10 -s icanhazip.com)

if [ -z "$CHECKIP" ]; then
    echo "ERROR_PROXY"
elif [ -z "$1" ]; then
    echo "SUCCESS_COMPLETED"
else
    echo "Start import proxy to $1"
    raw=$(cat ./tube_proxy.txt)
    raw="${raw//$'\r'/''}"
    raw="${raw//$'\n'/'\n'}"
    curl -X POST "http://$1/api/bulk-import-proxy-auto" -H 'Content-Type: application/json' -d "{\"raw\":\"$raw\",\"batch\":\"$IP4\",\"token\":\"taind\"}"
    echo "SUCCESS_COMPLETED"
fi
echo "...done..."
