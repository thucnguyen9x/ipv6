#!/bin/sh
#SCRIPT BY TAIND
cd ~

IP6PREFIXLEN=64
FIRST_PORT=10000
LAST_PORT=10299

send_telegram(){
    echo "$1"
}

WORKDATA=~/tube_data.txt

ulimit -n 1048576
if ! grep -q "UserTasksMax=60000" "/etc/systemd/system.conf" ; then
    echo "Seting linux limit"
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
fi

# sed -i '/nameserver/d' /etc/resolv.conf
# echo "nameserver 8.8.8.8" >> /etc/resolv.conf
# echo "nameserver 8.8.4.4" >> /etc/resolv.conf

pkill 3proxy
systemctl stop firewalld

echo "installing apps"
#yum -y install nano
yum -y install net-tools
yum -y install wget
yum -y install tar
yum install iptables-services -y

if iptables -S | grep -ce '-m state --state NEW -j ACCEPT'; then
    echo "Clear iptables"
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -F
    iptables -X
    sleep 2
    echo "Reboot to clear IPv6 maping"
    reboot
fi

echo "Getting IPv4 ..."
IP4=$(curl -4 -s icanhazip.com -m 10)
echo "Getting IPv6 ..."
IP6=$(curl -6 -s icanhazip.com -m 10)
echo "IPv4 = ${IP4}. IPv6 = ${IP6}"
[[ -z "$IP4" ]] && send_telegram "$IP4-ERROR_IPv4" && exit 1
[[ -z "$IP6" ]] && send_telegram "$IP4-ERROR_IPv6" && exit 1
NETNAME=$(ip -o -4 route get 8.8.8.8 | sed -nr 's/.*dev ([^\ ]+).*/\1/p') && [[ -z "$NETNAME" ]] && send_telegram "$IP4-ERROR_NETNAME" && exit 1

if grep "/48" /etc/sysconfig/network-scripts/ifcfg-$NETNAME; then
    IP6PREFIXLEN=48
elif grep "/52" /etc/sysconfig/network-scripts/ifcfg-$NETNAME; then
    IP6PREFIXLEN=52
elif grep "/56" /etc/sysconfig/network-scripts/ifcfg-$NETNAME; then
    IP6PREFIXLEN=56
elif grep "/80" /etc/sysconfig/network-scripts/ifcfg-$NETNAME; then
    IP6PREFIXLEN=80
elif grep "/96" /etc/sysconfig/network-scripts/ifcfg-$NETNAME; then
    IP6PREFIXLEN=96
elif grep "/112" /etc/sysconfig/network-scripts/ifcfg-$NETNAME; then
    IP6PREFIXLEN=112
else
    IP6PREFIXLEN=64
fi
#[[ $IP6PREFIXLEN -ne 48 ]] && [[ $IP6PREFIXLEN -ne 64 ]] && [[ $IP6PREFIXLEN -ne 80 ]] && send_telegram "ERROR_IP6PREFIXLEN" && exit 1
if [ $IP6PREFIXLEN -eq 48 ]; then
    IP6PREFIX=$(echo $IP6 | cut -f1-3 -d':')
elif [ $IP6PREFIXLEN -eq 52 ]; then
    IP6PREFIX=$(echo $IP6 | cut -f1-4 -d':')
elif [ $IP6PREFIXLEN -eq 56 ]; then
    IP6PREFIX=$(echo $IP6 | cut -f1-4 -d':')
elif [ $IP6PREFIXLEN -eq 64 ]; then
    IP6PREFIX=$(echo $IP6 | cut -f1-4 -d':')
elif [ $IP6PREFIXLEN -eq 80 ]; then
    IP6PREFIX=$(echo $IP6 | cut -f1-5 -d':')
elif [ $IP6PREFIXLEN -eq 96 ]; then
    IP6PREFIX=$(echo $IP6 | cut -f1-6 -d':')
elif [ $IP6PREFIXLEN -eq 112 ]; then
    IP6PREFIX=$(echo $IP6 | cut -f1-7 -d':')
fi

echo "IPv6 PrefixLen: $IP6PREFIXLEN --> Prefix: $IP6PREFIX"

rm -rf ~/tube_*
# rm -rf ~/*.tar.gz
# rm -rf ~/3proxy
# rm -rf ~/3proxy*

random() {
	tr </dev/urandom -dc A-Za-z0-9 | head -c5
	echo
}

install_3proxy() {
    echo "installing 3proxy"
    #wget -O 3proxy.tar.gz https://raw.githubusercontent.com/....
    tar -xzvf 3proxy.tar.gz
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp 3proxy/* /usr/local/etc/3proxy/bin/
}

gen_3proxy() {
    cat <<EOF
daemon
maxconn 20000
nserver 1.1.1.1
nserver 1.0.0.1
#nserver 8.8.8.8
#nserver 8.8.4.4
#nserver 2001:4860:4860::8888
#nserver 2001:4860:4860::8844
nscache 65536
nscache6 65535
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
stacksize 6291456
#config /usr/local/etc/3proxy/3proxy.cfg
#monitor /usr/local/etc/3proxy/3moniter.txt
#log /tmp/3proxy.log

authcache user 60
auth strong cache
#auth none
users pa43:CL:Poal43
allow pa43
$(awk -F "/" '{print "#auth strong cache\n" \
"#allow " $1 "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"#flush\n"}' ${WORKDATA})
EOF
}

gen_proxy_file_for_user() {
    cat >~/tube_proxy.txt <<EOF
$(awk -F "/" '{print "http://" $1 ":" $2 "@" $3 ":" $4 }' ${WORKDATA})
EOF
}

gen_data() {
    array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
    current=()
    ip64() {
		echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
	}
    seq $FIRST_PORT $LAST_PORT | while read port; do
        if [ $IP6PREFIXLEN -eq 48 ]; then
            echo "pa43/Poal43/$IP4/$port/$IP6PREFIX:$(ip64):$(ip64):$(ip64):$(ip64):$(ip64)"
        elif [ $IP6PREFIXLEN -eq 52 ]; then
            echo "pa43/Poal43/$IP4/$port/$IP6PREFIX:$(ip64):$(ip64):$(ip64):$(ip64)"
        elif [ $IP6PREFIXLEN -eq 56 ]; then
            echo "pa43/Poal43/$IP4/$port/$IP6PREFIX:$(ip64):$(ip64):$(ip64):$(ip64)"
        elif [ $IP6PREFIXLEN -eq 64 ]; then
            echo "pa43/Poal43/$IP4/$port/$IP6PREFIX:$(ip64):$(ip64):$(ip64):$(ip64)"
        elif [ $IP6PREFIXLEN -eq 80 ]; then
            echo "pa43/Poal43/$IP4/$port/$IP6PREFIX:$(ip64):$(ip64):$(ip64)"
        elif [ $IP6PREFIXLEN -eq 96 ]; then
            echo "pa43/Poal43/$IP4/$port/$IP6PREFIX:$(ip64):$(ip64)"
        elif [ $IP6PREFIXLEN -eq 112 ]; then
            curip=""
            for i in {1..7}
            do
                curip="pa43/Poal43/$IP4/$port/$IP6PREFIX:$(ip64)"
                if [[ ! " ${current[*]} " =~ " ${curip} " ]]; then
                    break
                fi
            done
            current+=("$curip")
            echo $curip
        fi
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
$(awk -v NETNAME="$NETNAME" -v IP6PREFIXLEN="$IP6PREFIXLEN" -F "/" '{print "ifconfig " NETNAME " inet6 add " $5 "/" IP6PREFIXLEN}' ${WORKDATA})
set -e
EOF
}

clear_old_proxy_ip(){
    pattern="(\w+:\w+:\w+:\w+:\w+:\w+:\w+:\w+\/$IP6PREFIXLEN)"
    ip a > ipconfigdata.txt
    for n in $(cat ipconfigdata.txt)
    do
        if [[ $n =~ $pattern ]] && [[ $n != *":0:0:0:"* ]] && [[ $n != *":0000:0000:0000:"* ]] && [[ $ipv6init != *":0:0:0:"* ]]; then
            echo "Delete ${BASH_REMATCH[1]}"
            ifconfig $NETNAME del ${BASH_REMATCH[1]}
        fi
    done
}

install_3proxy
#clear_old_proxy_ip

echo "Gen data"
gen_data >$WORKDATA
gen_iptables >~/tube_iptables.sh
gen_ifconfig >~/tube_ifconfig.sh
echo "----" > /tmp/3proxy.log
chmod a+rwx,u+rwx,g+rwx,o+rwx /tmp/3proxy.log
echo $(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 32 | head -n 1) >/usr/local/etc/3proxy/3moniter.txt
gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg
chmod a+rwx,u+rwx,g+rwx,o+rwx tube_* /usr/local/etc/3proxy/bin/3proxy
echo "Run tube_iptables"
~/tube_iptables.sh
sleep 5
echo "Run tube_ifconfig"
~/tube_ifconfig.sh
sleep 5
echo "Run 3proxy"
/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
gen_proxy_file_for_user

echo "Wait 10s for proxy ready"
sleep 10

SERVER=""
DEMOPROXY="http://pa43:Poal43@${IP4}:${LAST_PORT}"
CHECKIP=$(curl -x "${DEMOPROXY}" --connect-timeout 10 -s icanhazip.com)
echo "${IP4}:${LAST_PORT}  -->  ${CHECKIP}"
if [[ -z "$CHECKIP" ]] || [[ ! "$CHECKIP" == *"$IP6PREFIX"* ]]; then
    echo "ERROR_PROXY"
    send_telegram "$IP4-ERROR-PROXY"
else
    send_telegram "$IP4-SUCCESS"
fi
echo "...done..."