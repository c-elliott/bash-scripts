#!/bin/bash
# This script is designed to run as a cronjob to manage
# Physical CPU:Virtual CPU assignments on Xen Hypervisors
# for improved performance and stability.

# Allocation mode
#   basic      = Assigns each VCPU to Physical CPU from first to last
#   sequential = Assigns each VCPU to a Physical CPU sequentially, for more even allocation
MODE="sequential"

## Do not edit below this line ##

LOCKFILE=/etc/xen/xen-cpuaffinity.lock
export PATH=$PATH:/bin:/usr/bin:/sbin:/usr/sbin

# Kill existing process if exists
if [[ -e $LOCKFILE ]]; then
  kill -9 $(cat $LOCKFILE) &>/dev/null
  rm -f $LOCKFILE
  sleep 2
fi

# Create lockfile
PID=$$
echo $PID > $LOCKFILE

# Identify usable CPUs
DOM_CHECK=$(xl vcpu-list | awk '/Domain-0/ { print $NF }' | head -n1 | grep -c ",")
if [[ $DOM_CHECK == "1" ]]; then
    NUM_CPUS=$(xl vcpu-list | awk '/Domain-0/ { print $NF }' | head -n1)
    DOM_CPUS=$(xl vcpu-list | awk '/Domain-0/ { print $(NF-2) }' | head -n1)
    USE_CPUS=$(echo $NUM_CPUS | sed "s/${DOM_CPUS},//")
else
    NUM_CPUS=$(xl info | grep nr_cpus | awk '{ print $NF }')
    DOM_CPUS=$(xl vcpu-list Domain-0 | tail -n +2 | awk '{ print $4 }' | xargs | sed 's/ /,/g')
    USE_CPUS=0
    for CPU in $(seq 1 $(expr $NUM_CPUS - 1)); do
        USE_CPUS="${USE_CPUS},$CPU"
    done
    USE_CPUS=$(echo $USE_CPUS | sed "s/${DOM_CPUS},//")
fi
echo "Assigned for Dom0  = $DOM_CPUS"
echo "Available for DomU = $USE_CPUS"

# Allocate
if [[ $MODE == "sequential" ]]; then
    # Ensure the list is long enough
    SEQ_CPUS=$USE_CPUS
    for VM in $(xl vcpu-list | grep vm | awk '{ print $1 }') ; do
        SEQ_CPUS="${SEQ_CPUS},${USE_CPUS}"
    done
    SEQ_CPUS="${SEQ_CPUS},${SEQ_CPUS},${SEQ_CPUS}"
    echo "Generated sequential list of CPUs for mapping"
    # Allocate
    echo "Allocating VCPU to CPU"
    NAME=""
    SEQN=1
    for VM in $(xl vcpu-list | grep vm | awk '{ print $1 }') ; do
        if [[ $NAME != $VM ]]; then
            NAME=$VM
            echo " ---- $VM ----"
            COUNT=1
        fi
        PCPU=$(echo $SEQ_CPUS | cut -d ',' -f $SEQN)
        VCPU=$(expr $COUNT - 1)
        echo " > VCPU $VCPU to CPU $PCPU"
        xl vcpu-pin $NAME $VCPU $PCPU $PCPU
        ((COUNT++))
        ((SEQN++))
    done
elif [[ $MODE == "basic" ]]; then
    echo "Allocating VCPU to CPU"
    NAME=""
    for VM in $(xl vcpu-list | grep vm | awk '{ print $1 }') ; do
        if [[ $NAME != $VM ]]; then
            NAME=$VM
            echo " ---- $VM ----"
            COUNT=1
        fi
        VCPU=$(expr $COUNT - 1)
        echo " > VCPU $VCPU to $USE_CPUS"
        xl vcpu-pin $NAME $VCPU $USE_CPUS $USE_CPUS
        ((COUNT++))
    done
else
    echo "Unknown mode. Failed to allocate"
fi

# Remove lockfile
rm -f $LOCKFILE
