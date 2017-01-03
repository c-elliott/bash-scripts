#!/bin/bash
# Filename....: kvm-monitor-virtualizor.sh
# Description.: Aggregates statistics for KVM resource abuse tracking on Virtualizor
# Chris Elliott -- https://github.com/c-elliott

# Installation
# 1. Save this script e.g. /etc/kvm-monitor-virtualizor.sh
# 2. Make it executable for root only, chmod 770 /etc/kvm-monitor-virtualizor.sh
# 3. Add to crontab with desired interval.
# Example: */10 * * * * /etc/kvm-monitor-virtualizor.sh -a 2>/dev/null

# Settings
HOST_INT="viifbr0"                              # Host network interface to monitor
HOST_HDD="sda"                                  # Host block device to monitor
LVM_VG="vg"                                     # LVM volume group for guests
ALERT_ADDRESS="email@address.com"               # Email address for alerts
ALERT_SUBJECT="KVM Monitor Alert on $HOSTNAME"  # Subject for email alerts
ALERT_IO_READS="100"                            # Alert if IO reads remains above this value at next interval
ALERT_IO_WRITES="100"                           # Alert if IO writes remains above this value at next interval
ALERT_TX_PPS="1000"                             # Alert if outbound PPS remains above this value at next interval
ALERT_RX_PPS="1000"                             # Alert if inbound PPS remains above this value at next interval

        ############# DO NOT EDIT BELOW THIS LINE #############

# Provide syntax help
if [ $# -eq 0 ]; then
  echo "Syntax: ./kvm-monitor-virtualizor.sh <option>"
  echo "    -a = Run alerts, e.g. for crontab"
  echo "    -m = Run manually without alerts"
  echo "    -v = View results of previous run"
  echo
  exit 0
fi

# View previous results
if [ $1 = "-v" ] && [ -e /tmp/kvm-monitor.txt ]; then
  less /tmp/kvm-monitor.txt
  exit 0
elif [ $1 = "-v" ] && [ ! -e /tmp/kvm-monitor.txt ]; then
  echo "Cannot locate previous data. Please run with -m option."
  exit 1
fi

# Check dependancies
if [ `which virt-top | grep -c no` = "1" ] || [ `which virsh | grep -c no` = "1" ] || \
   [ `which iostat | grep -c no` = "1" ] || [ `which bc | grep -c no` = "1" ] || \
   [ `which column | grep -c no` = "1" ] || [ `which mail | grep -c no` = "1" ] || \
   [ `which less | grep -c no` = "1" ]; then
  echo "ERROR! One of the required binaries is not in your PATH."
  echo "Requires: virt-top virsh iostat column bc mail less"
  exit 2
fi

# Mail function
alertmail() {
  echo $1 | mail -s "$ALERT_SUBJECT" $ALERT_ADDRESS
}

# Obtain virt-top & iostat data
echo "Collecting data, please wait..."
virt-top --stream -n 2 > /tmp/virttop.tmp
LINE_NUM=`grep -w "ID S RDRQ" -n /tmp/virttop.tmp| tail -1 | cut -d: -f1`
sed -n ''$LINE_NUM',$p' /tmp/virttop.tmp > /tmp/virttop-output.tmp
iostat -Nx > /tmp/iostat-lv.tmp

# Obtain vm list in nice format
VT_VMNAME=`tail -n +2 /tmp/virttop-output.tmp | awk '{ print $10 }' | xargs`

# Obtain network stats in parallel
for VM in $VT_VMNAME; do
(
  # Calculate Guest RX/TX
  R1=`cat /sys/class/net/viif${VM}/statistics/rx_bytes`
  T1=`cat /sys/class/net/viif${VM}/statistics/tx_bytes`
  sleep 1
  R2=`cat /sys/class/net/viif${VM}/statistics/rx_bytes`
  T2=`cat /sys/class/net/viif${VM}/statistics/tx_bytes`
  TBPS=`expr $T2 - $T1`
  RBPS=`expr $R2 - $R1`
  TKBPS=`expr $TBPS / 1024`
  RKBPS=`expr $RBPS / 1024`

  # Calculate Guest PPS
  R1=`cat /sys/class/net/viif${VM}/statistics/rx_packets`
  T1=`cat /sys/class/net/viif${VM}/statistics/tx_packets`
  sleep 1
  R2=`cat /sys/class/net/viif${VM}/statistics/rx_packets`
  T2=`cat /sys/class/net/viif${VM}/statistics/tx_packets`
  TXPPS=`expr $T2 - $T1`
  RXPPS=`expr $R2 - $R1`

  echo "$VM $TKBPS $RKBPS $TXPPS $RXPPS" >> /tmp/kvm-netstats.tmp

) &
done
wait

# Start building a table full of information
echo "VMNAME CPUS CPU(%) MEM HDD(r/s) HDD(w/s) TX(kB/s) RX(kB/s) TX(pps) RX(pps)" > /tmp/kvm-monitor.tmp

# Prepare Host information
HOST_CPU=`top -n 1 | grep Cpu | awk '{ print $2 }'| cut -f1 -d"%"`
HOST_MEM=`free | grep Mem | awk '{print $3/$2 * 100.0}'`
HOST_IO=`grep $HOST_HDD /tmp/iostat-lv.tmp | awk '{ print $4, $5 }' | xargs`

# Calculate Host RX/TX
R1=`cat /sys/class/net/${HOST_INT}/statistics/rx_bytes`
T1=`cat /sys/class/net/${HOST_INT}/statistics/tx_bytes`
sleep 1
R2=`cat /sys/class/net/${HOST_INT}/statistics/rx_bytes`
T2=`cat /sys/class/net/${HOST_INT}/statistics/tx_bytes`
TBPS=`expr $T2 - $T1`
RBPS=`expr $R2 - $R1`
TKBPS=`expr $TBPS / 1024`
RKBPS=`expr $RBPS / 1024`

# Calculate Host PPS
R1=`cat /sys/class/net/${HOST_INT}/statistics/rx_packets`
T1=`cat /sys/class/net/${HOST_INT}/statistics/tx_packets`
sleep 1
R2=`cat /sys/class/net/${HOST_INT}/statistics/rx_packets`
T2=`cat /sys/class/net/${HOST_INT}/statistics/tx_packets`
TXPPS=`expr $T2 - $T1`
RXPPS=`expr $R2 - $R1`

# Populate Host information
echo "HOST `nproc` ${HOST_CPU} `echo \"scale=1;${HOST_MEM}/1" | bc` ${HOST_IO} $TKBPS $RKBPS $TXPPS $RXPPS" >> /tmp/kvm-monitor.tmp

# Start populating Guest information
ROW="1"
for VM in $VT_VMNAME; do
  PT_1=`tail -n +2 /tmp/virttop-output.tmp | awk '{ print $10 }' | awk NR==$ROW`
  PT_2="$PT_1 `virsh vcpucount $VM | grep current | grep live | awk '{ print $3 }'` `tail -n +2 /tmp/virttop-output.tmp | awk '{ print $7, $8 }' | awk NR==$ROW`"
  PT_3="$PT_2 `grep -m 1 $VM /tmp/iostat-lv.tmp | awk '{ print $4, $5 }' | xargs`"
  PT_4="$PT_3 `cat /tmp/kvm-netstats.tmp | grep $VM | awk '{ print $2, $3, $4, $5 }'`"
  echo $PT_4 >> /tmp/kvm-monitor.tmp
  ((ROW++))
done

# Complete and sort the table
cat /tmp/kvm-monitor.tmp | head -2 > /tmp/kvm-monitor1.tmp
cat /tmp/kvm-monitor.tmp | tail -n +3 | sort -n -r -k 2 >> /tmp/kvm-monitor1.tmp
column -t /tmp/kvm-monitor1.tmp > /tmp/kvm-monitor.txt
sed -i '1i kvm-custom.sh : KVM resource abuse monitoring' /tmp/kvm-monitor.txt
sed -i '2i ====================================================================================' /tmp/kvm-monitor.txt

# Display table if running manually
if [ $1 = "-m" ]; then
  clear
  cat /tmp/kvm-monitor.txt
fi

# Handle alerts
if [ $1 = "-a" ]; then
  echo "WARNING!"
  echo "Are you running me manually in alert mode?"
  echo "If so its normal to see operand errors for where we have 0 or NULL values."
  echo "Use ./kvm-monitor-virtualizor.sh -a 2>/dev/null"
  sleep 10
  for VM in $VT_VMNAME; do
    VM_READ=$(echo "(`grep $VM /tmp/kvm-monitor.txt | awk '{ print $5 }'`+0.5)/1" | bc)
    if [ $VM_READ -ge $ALERT_IO_READS ] && [ -e /tmp/alert-io-reads-${VM} ]; then
      alertmail "$VM has exceeded the ALERT_IO_READS threshold of $ALERT_IO_READS"
      rm -f /tmp/alert-io-reads-${VM}
    elif [ $VM_READ -ge $ALERT_IO_READS ] && [ ! -e /tmp/alert-io-reads-${VM} ]; then
      touch /tmp/alert-io-reads-${VM}
    else
      rm -f /tmp/alert-io-reads-${VM}
    fi
    VM_WRITE=$(echo "(`grep $VM /tmp/kvm-monitor.txt | awk '{ print $6 }'`+0.5)/1" | bc)
    if [ $VM_WRITE -ge $ALERT_IO_WRITES ] && [ -e /tmp/alert-io-writes-${VM} ]; then
      alertmail "$VM has exceeded the ALERT_IO_WRITES threshold of $ALERT_IO_WRITES"
      rm -f /tmp/alert-io-writes-${VM}
    elif [ $VM_WRITE -ge $ALERT_IO_WRITES ] && [ ! -e /tmp/alert-io-writes-${VM} ]; then
      touch /tmp/alert-io-writes-${VM}
    else
      rm -f /tmp/alert-io-writes-${VM}
    fi
    if [ `grep $VM /tmp/kvm-monitor.txt | awk '{ print $9 }'` -ge $ALERT_TX_PPS ] && [ -e /tmp/alert-tx-pps-${VM} ]; then
      alertmail "$VM has exceeded the ALERT_TX_PPS threshold of $ALERT_TX_PPS"
      rm -f /tmp/alert-tx-pps-${VM}
    elif [ `grep $VM /tmp/kvm-monitor.txt | awk '{ print $9 }'` -ge $ALERT_TX_PPS ] && [ ! -e /tmp/alert-tx-pps-${VM} ]; then
      touch /tmp/alert-tx-pps-${VM}
    else
      rm -f /tmp/alert-tx-pps-${VM}
    fi
    if [ `grep $VM /tmp/kvm-monitor.txt | awk '{ print $10 }'` -ge $ALERT_RX_PPS ] && [ -e /tmp/alert-rx-pps-${VM} ]; then
      alertmail "$VM has exceeded the ALERT_RX_PPS threshold of $ALERT_RX_PPS"
      rm -f /tmp/alert-rx-pps-${VM}
    elif [ `grep $VM /tmp/kvm-monitor.txt | awk '{ print $10 }'` -ge $ALERT_RX_PPS ] && [ ! -e /tmp/alert-rx-pps-${VM} ]; then
      touch /tmp/alert-rx-pps-${VM}
    else
      rm -f /tmp/alert-rx-pps-${VM}
    fi
  done
fi

# Cleanup
rm -f /tmp/kvm-monitor.tmp /tmp/kvm-monitor1.tmp /tmp/virttop-output.tmp /tmp/kvm-netstats.tmp /tmp/virttop.tmp /tmp/virttop-output.tmp /tmp/iostat-lv.tmp
