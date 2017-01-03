#!/bin/bash
# Filename...: vz-monitor.sh
# Description: Aggregates statistics for OpenVZ+SolusVM resource abuse tracking
# Chris Elliott -- https://github.com/c-elliott

# Remove old files
rm -f /tmp/vz-*tmp

# Find out release version
if [ `awk '{ print $3 }' /etc/redhat-release | cut -d . -f1` == "5" ]; then
  release="el5"
elif [ `awk '{ print $3 }' /etc/redhat-release | cut -d . -f1` == "6" ]; then
  release="el6"
else
  echo "Unsupported release. Is this CentOS/RHEL?"
  exit 0
fi

# Initial message
echo -e "\n Detected System: $release"
echo -e " Please wait while we gather statistics..."
echo -e "\n Note:\n Bandwidth stats are based on primary IP's only, sampled over 5 seconds."
echo -e " HDD/IO stats are based on OpenVZ ioacct data, sampled over 5 seconds. \n"

# Obtain first set of networking statistics
iptables -L SOLUSVM_TRAFFIC_IN -n -x -v > /tmp/vz-net1-rx.tmp
iptables -L SOLUSVM_TRAFFIC_OUT -n -x -v > /tmp/vz-net1-tx.tmp

# Obtain vm list in a nice format
vmlist=`vzlist | awk '{ print $1 }' | sed "1 d" | xargs`

# Obtain IO, Load statistics in parallel
for i in $vmlist; do
  (
    if [ "$release" == "el5" ]; then
      read1=`grep vfs_reads /proc/bc/${i}/ioacct | awk '{ print $2 }'`
      write1=`grep vfs_writes /proc/bc/${i}/ioacct | awk '{ print $2 }'`
      sleep 5
      read2=`grep vfs_reads /proc/bc/${i}/ioacct | awk '{ print $2 }'`
      write2=`grep vfs_writes /proc/bc/${i}/ioacct | awk '{ print $2 }'`
    else
      read1=`grep read /proc/bc/${i}/ioacct | awk '{ print $2 }'`
      write1=`grep write /proc/bc/${i}/ioacct | awk '{ print $2 }'`
      sleep 5
      read2=`grep read /proc/bc/${i}/ioacct | awk '{ print $2 }'`
      write2=`grep write /proc/bc/${i}/ioacct | awk '{ print $2 }'`
    fi      
    ct_reads=`expr $read2 - $read1`
    ct_writes=`expr $write2 - $write1`
    ct_load=`vzlist $i -o laverage | sed '1 d' | cut -d / -f 1`
    echo "$i $ct_load $ct_reads $ct_writes" >> /tmp/vz-monitor.tmp
  ) &
done
wait

# Obtain second set of networking statistics
iptables -L SOLUSVM_TRAFFIC_IN -n -x -v > /tmp/vz-net2-rx.tmp
iptables -L SOLUSVM_TRAFFIC_OUT -n -x -v > /tmp/vz-net2-tx.tmp

# Populate VM information
row="1"
for i in $vmlist; do
  # Calculate VPS RX/TX
  ct_ip=`vzlist $i | awk 'NR==2 { print $4 }'`
  ct_rx1=`grep -w $ct_ip /tmp/vz-net1-rx.tmp | awk '{ print $2 }'`
  ct_rx2=`grep -w $ct_ip /tmp/vz-net2-rx.tmp | awk '{ print $2 }'`
  ct_tx1=`grep -w $ct_ip /tmp/vz-net1-tx.tmp | awk '{ print $2 }'`
  ct_tx2=`grep -w $ct_ip /tmp/vz-net2-tx.tmp | awk '{ print $2 }'`
  ct_rx=`expr $ct_rx2 - $ct_rx1`
  ct_tx=`expr $ct_tx2 - $ct_tx1`

  # Add information to table
  pt_1=`cat /tmp/vz-monitor.tmp | awk NR==$row`
  pt_2="$pt_1 `expr $ct_tx / 1024` `expr $ct_rx / 1024`"
  echo $pt_2 >> /tmp/vz-monitor2.tmp
  ((row++))
done

# Complete and sort the table
sed -i '1i VMNAME LOAD HDD(r/5sec) HDD(w/5sec) TX(kB/5sec) RX(kB/5sec)' /tmp/vz-monitor2.tmp
column -t /tmp/vz-monitor2.tmp > /tmp/vz-monitor.txt
sed -i '1i vz-monitor.sh : https://github.com/c-elliott' /tmp/vz-monitor.txt
sed -i '2i ====================================================================================' /tmp/vz-monitor.txt

# Display table
clear
cat /tmp/vz-monitor.txt
