#!/bin/bash
# Filename...: kvm-monitor.sh
# Description: Aggregates statistics for KVM resource abuse tracking
# Chris Elliott -- https://github.com/c-elliott

# General Settings
dom0_int="eth0"                        # Dom0 (Host) network interface to check
dom0_hdd="sda"                         # Dom0 (Host) filesystem to check
domu_vif="0"                           # DomU (Guest) virtual interface to check

	############# DO NOT EDIT BELOW THIS LINE #############

# Check for some dependancies
if [ ! -f "/usr/bin/virt-top" ]; then
  echo "ERROR! - I can't find the virt-top binary"
  exit 0
elif [ ! -f "/usr/bin/iostat" ]; then
  echo "ERROR! - I can't find the iostat binary"
  exit 0
elif [ ! -f "/usr/bin/bc" ]; then
  echo "ERROR! - I can't find the bc binary"
  exit 0
fi

# Obtain virt-top & iostat data
echo "Collecting data, please wait..."
virt-top --stream -n 2 > /tmp/virttop.tmp
line_num=`grep -w "ID S RDRQ" -n /tmp/virttop.tmp| tail -1| cut -d: -f1`
sed -n ''$line_num',$p' /tmp/virttop.tmp > /tmp/virttop-output.tmp
iostat -Nx > /tmp/iostat-lv.tmp

# Obtain vm list in nice format
xt_vmname=`tail -n +2 /tmp/virttop-output.tmp | awk '{ print $10 }' | xargs`

# Clear previous network statistics
echo > /tmp/kvm-netstats.tmp

# Obtain network stats in parallel
for vm in $xt_vmname; do
(
  # Calculate VPS RX/TX
  R1=`cat /sys/class/net/${vm}.${domu_vif}/statistics/rx_bytes`
  T1=`cat /sys/class/net/${vm}.${domu_vif}/statistics/tx_bytes`
  sleep 1
  R2=`cat /sys/class/net/${vm}.${domu_vif}/statistics/rx_bytes`
  T2=`cat /sys/class/net/${vm}.${domu_vif}/statistics/tx_bytes`
  TBPS=`expr $T2 - $T1`
  RBPS=`expr $R2 - $R1`
  TKBPS=`expr $TBPS / 1024`
  RKBPS=`expr $RBPS / 1024`

  # Calculate VPS PPS
  R1=`cat /sys/class/net/${vm}.${domu_vif}/statistics/rx_packets`
  T1=`cat /sys/class/net/${vm}.${domu_vif}/statistics/tx_packets`
  sleep 1
  R2=`cat /sys/class/net/${vm}.${domu_vif}/statistics/rx_packets`
  T2=`cat /sys/class/net/${vm}.${domu_vif}/statistics/tx_packets`
  TXPPS=`expr $T2 - $T1`
  RXPPS=`expr $R2 - $R1`

  echo "$vm $TKBPS $RKBPS $TXPPS $RXPPS" >> /tmp/kvm-netstats.tmp

) &
done
wait

# Start building a table full of information
echo "VMNAME CPUS CPU(%) MEM HDD(r/s) HDD(w/s) TX(kB/s) RX(kB/s) TX(pps) RX(pps)" > /tmp/kvm-monitor.tmp

# Prepare Domain-0 (Host) information
dom0_cpu=`top -n 1 | grep Cpu | awk '{ print $2 }'| cut -f1 -d"%"`
dom0_mem=`free | grep Mem | awk '{print $3/$2 * 100.0}'`
dom0_io=`grep ${dom0_hdd} /tmp/iostat-lv.tmp | awk '{ print $4, $5 }' | xargs`

# Calculate Domain-0 RX/TX
R1=`cat /sys/class/net/${dom0_int}/statistics/rx_bytes`
T1=`cat /sys/class/net/${dom0_int}/statistics/tx_bytes`
sleep 1
R2=`cat /sys/class/net/${dom0_int}/statistics/rx_bytes`
T2=`cat /sys/class/net/${dom0_int}/statistics/tx_bytes`
TBPS=`expr $T2 - $T1`
RBPS=`expr $R2 - $R1`
TKBPS=`expr $TBPS / 1024`
RKBPS=`expr $RBPS / 1024`

# Calculate Domain-0 PPS
R1=`cat /sys/class/net/${dom0_int}/statistics/rx_packets`
T1=`cat /sys/class/net/${dom0_int}/statistics/tx_packets`
sleep 1
R2=`cat /sys/class/net/${dom0_int}/statistics/rx_packets`
T2=`cat /sys/class/net/${dom0_int}/statistics/tx_packets`
TXPPS=`expr $T2 - $T1`
RXPPS=`expr $R2 - $R1`

# Populate Domain-0 (Host) information
echo "Domain-0 `nproc` ${dom0_cpu} `echo \"scale=1;${dom0_mem}/1" | bc` ${dom0_io} $TKBPS $RKBPS $TXPPS $RXPPS" >> /tmp/kvm-monitor.tmp

# Start populating DomU (Guest) information
row="1"
for vm in $xt_vmname; do
  vm_cpus=`virsh vcpucount $vm | grep current | grep live | awk '{ print $3 }'`
  pt_1=`tail -n +2 /tmp/virttop-output.tmp | awk '{ print $10 }' | awk NR==$row`
  pt_2="$pt_1 $vm_cpus `tail -n +2 /tmp/virttop-output.tmp | awk '{ print $7, $8 }' | awk NR==$row`"
  pt_3="$pt_2 `grep "${vm}_img" /tmp/iostat-lv.tmp | awk '{ print $4, $5 }' | xargs`"
  pt_4="$pt_3 `cat /tmp/kvm-netstats.tmp | grep $vm | awk '{ print $2, $3, $4, $5 }'`"
  echo $pt_4 >> /tmp/kvm-monitor.tmp
  ((row++))
done

# Complete and sort the table
cat /tmp/kvm-monitor.tmp | head -2 > /tmp/kvm-monitor1.tmp
cat /tmp/kvm-monitor.tmp | tail -n +3 | sort -n -r -k 2 >> /tmp/kvm-monitor1.tmp
column -t /tmp/kvm-monitor1.tmp > /tmp/kvm-monitor.txt
sed -i '1i kvm-monitor.sh : https://github.com/c-elliott' /tmp/kvm-monitor.txt
sed -i '2i ====================================================================================' /tmp/kvm-monitor.txt

# Display table
clear
cat /tmp/kvm-monitor.txt
