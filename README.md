config="/etc/sysconfig/network-scripts/ifcfg-$(ip -o -4 route get 8.8.8.8 | sed -nr 's/.*dev ([^\ ]+).*/\1/p')"
echo "IPV6_FAILURE_FATAL=no" >> $config
echo "IPV6_ADDR_GEN_MODE=stable-privacy" >> $config
echo "IPV6ADDR=2407:5b40:0:c26::325/64" >> $config
echo "IPV6_DEFAULTGW=2407:5b40:0:c26::1" >> $config
