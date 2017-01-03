#!/bin/bash
# Filename...: xen-monitor.sh
# Description: Aggregates statistics for Xen resource abuse tracking
# Chris Elliott -- https://github.com/c-elliott

# Network Settings
DOM0_INT="xenbr0"         # Dom0 network interface to check
DOMU_VIF="0"              # DomU virtual interface to check
DOMU_VIF_PREFIX=""        # DomU virtual interface prefix e.g. vifvm

        ############# DO NOT EDIT BELOW THIS LINE #############

# Check for some dependancies
if [ `which xentop | grep -c no` = "1" ]; then
  echo "ERROR! - I can't find the xentop binary"
  exit 101
elif [ `which iostat | grep -c no` = "1" ]; then
  echo "ERROR! - I can't find the iostat binary"
  exit 102
elif [ `which column | grep -c no` = "1" ]; then
  echo "ERROR! - I can't find the column binary"
  exit 103
fi

# Obtain xentop & iostat data
echo "Collecting data, please wait..."
xentop -b -i 2 -d 1 > /tmp/xentop.tmp
iostat -Nx > /tmp/iostat-lv.tmp

# Obtain vm list in nice format
XT_VMNAME=`sed '1,/NAME/d' /tmp/xentop.tmp | awk '{ print $1 }' | xargs`

# Obtain network stats in parallel
for VM in $XT_VMNAME; do
(
  if [ $VM != "Domain-0" ]; then
    VMNO=`echo $VM | sed 's/vm//'`

    # Calculate VPS RX/TX
    R1=`cat /sys/class/net/${DOMU_VIF_PREFIX}${VMNO}.${DOMU_VIF}/statistics/rx_bytes`
    T1=`cat /sys/class/net/${DOMU_VIF_PREFIX}${VMNO}.${DOMU_VIF}/statistics/tx_bytes`
    sleep 1
    R2=`cat /sys/class/net/${DOMU_VIF_PREFIX}${VMNO}.${DOMU_VIF}/statistics/rx_bytes`
    T2=`cat /sys/class/net/${DOMU_VIF_PREFIX}${VMNO}.${DOMU_VIF}/statistics/tx_bytes`
    TBPS=`expr $T2 - $T1`
    RBPS=`expr $R2 - $R1`
    TKBPS=`expr $TBPS / 1024`
    RKBPS=`expr $RBPS / 1024`

    # Calculate VPS PPS
    R1=`cat /sys/class/net/${DOMU_VIF_PREFIX}${VMNO}.${DOMU_VIF}/statistics/rx_packets`
    T1=`cat /sys/class/net/${DOMU_VIF_PREFIX}${VMNO}.${DOMU_VIF}/statistics/tx_packets`
    sleep 1
    R2=`cat /sys/class/net/${DOMU_VIF_PREFIX}${VMNO}.${DOMU_VIF}/statistics/rx_packets`
    T2=`cat /sys/class/net/${DOMU_VIF_PREFIX}${VMNO}.${DOMU_VIF}/statistics/tx_packets`
    TXPPS=`expr $T2 - $T1`
    RXPPS=`expr $R2 - $R1`
  
  else

    # Calculate Domain-0 RX/TX
    R1=`cat /sys/class/net/${DOM0_INT}/statistics/rx_bytes`
    T1=`cat /sys/class/net/${DOM0_INT}/statistics/tx_bytes`
    sleep 1
    R2=`cat /sys/class/net/${DOM0_INT}/statistics/rx_bytes`
    T2=`cat /sys/class/net/${DOM0_INT}/statistics/tx_bytes`
    TBPS=`expr $T2 - $T1`
    RBPS=`expr $R2 - $R1`
    TKBPS=`expr $TBPS / 1024`
    RKBPS=`expr $RBPS / 1024`

    # Calculate Domain-0 PPS
    R1=`cat /sys/class/net/${DOM0_INT}/statistics/rx_packets`
    T1=`cat /sys/class/net/${DOM0_INT}/statistics/tx_packets`
    sleep 1
    R2=`cat /sys/class/net/${DOM0_INT}/statistics/rx_packets`
    T2=`cat /sys/class/net/${DOM0_INT}/statistics/tx_packets`
    TXPPS=`expr $T2 - $T1`
    RXPPS=`expr $R2 - $R1`
  fi

  echo "$VM $TKBPS $RKBPS $TXPPS $RXPPS" >> /tmp/xen-netstats.tmp

) &
done
wait

# Start building a table full of information
echo "VMNAME CPU(%) MEM IMG(r/s) IMG(w/s) SWAP(r/s) SWAP(w/s) TX(kB/s) RX(kB/s) TX(pps) RX(pps)" > /tmp/xen-monitor.tmp

# Start populating
ROW="1"
for VM in $XT_VMNAME; do
  pt_1=`sed '1,/NAME/d' /tmp/xentop.tmp | awk '{ print $1, $4, $6 }' | awk NR==$ROW`
  pt_2="$pt_1 `grep "${VM}_img\|${VM}_swap" /tmp/iostat-lv.tmp | awk '{ print $4, $5 }' | xargs`"
  if [ `echo ${pt_2} | awk '{print NF}'` == "5" ]; then
    pt_3="$pt_2 NONE NONE"
  elif [ `echo ${pt_2} | awk '{print NF}'` == "3" ]; then
    pt_3="$pt_2 NONE NONE NONE NONE"
  else
    pt_3="$pt_2"
  fi
  pt_4="$pt_3 `cat /tmp/xen-netstats.tmp | grep $VM | awk '{ print $2, $3, $4, $5 }'`"
  echo $pt_4 >> /tmp/xen-monitor.tmp
  ((ROW++))
done

# Complete and sort the table
cat /tmp/xen-monitor.tmp | head -2 > /tmp/xen-monitor1.tmp
cat /tmp/xen-monitor.tmp | tail -n +3 | sort -n -r -k 2 >> /tmp/xen-monitor1.tmp
column -t /tmp/xen-monitor1.tmp > /tmp/xen-monitor.txt
sed -i '1i xen-monitor.sh : https://github.com/c-elliott' /tmp/xen-monitor.txt
sed -i '2i ====================================================================================================' /tmp/xen-monitor.txt

# Display table
clear
cat /tmp/xen-monitor.txt

# Cleanup
rm -f /tmp/xen-monitor.tmp /tmp/xen-monitor1.tmp /tmp/xentop.tmp /tmp/iostat-lv.tmp /tmp/xen-netstats.tmp
