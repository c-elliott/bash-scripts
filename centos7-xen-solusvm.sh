#!/bin/bash
# Filename...: centos7-xen-solusvm.sh
# Description: Automated configuration of Xen for SolusVM systems
# Chris Elliott -- https://github.com/c-elliott

# Initial message and confirmation prompt
clear
echo -e "\n centos7-xen-solusvm.sh -- https://github.com/c-elliott \n ------------------------------------------------------"
echo -e "\n This script will configure a bare/clean CentOS 7 system ready to host Xen \n Virtual Machines with the SolusVM control panel. The configuration options \n are based on many years experience managing thousands of VMs, however \n they make not be optimal for your environment. \n \n Shall we begin?"
echo -e "\n Option (y or n):"
read startprompt
if [ "$startprompt" != "y" ]; then
  exit 0
fi

# Check if SolusVM is installed
if [ ! -e "/usr/local/solusvm" ]; then
  clear
  echo -e "\n ERROR \n Please install SolusVM Slave with Xen using the V4 installer:"
  echo -e "URL: https://documentation.solusvm.com/display/DOCS/SolusVM+Installer++-+Version+4 \n"
  exit 0
fi

# Install additional packages
yum clean all
yum -y install epel-release
yum -y install libcgroup irqbalance ntp sysstat iftop iotop vnstat tar wget openssh-clients rsync

# Remove any default iptables rules
iptables -F
cp -n /etc/sysconfig/iptables /etc/sysconfig/iptables.bak
echo > /etc/sysconfig/iptables

# Disable all services in systemd
for service in `systemctl list-unit-files | grep enabled | awk '{ print $1 }'`; do
  systemctl disable $service > /dev/null 2>&1
done

# Enable required services
systemctl enable atd.service > /dev/null 2>&1
systemctl enable auditd.service > /dev/null 2>&1
systemctl enable crond.service > /dev/null 2>&1
systemctl enable dhcpd.service > /dev/null 2>&1
systemctl enable getty@.service > /dev/null 2>&1
systemctl enable ip6tables.service > /dev/null 2>&1
systemctl enable iptables.service > /dev/null 2>&1
systemctl enable irqbalance.service > /dev/null 2>&1
systemctl enable lm_sensors.service > /dev/null 2>&1
systemctl enable lvm2-monitor.service > /dev/null 2>&1
systemctl enable mdmonitor.service > /dev/null 2>&1
systemctl enable microcode.service > /dev/null 2>&1
systemctl enable postfix.service > /dev/null 2>&1
systemctl enable rsyslog.service > /dev/null 2>&1
systemctl enable smartd.service > /dev/null 2>&1
systemctl enable sshd.service > /dev/null 2>&1
systemctl enable svmstack-nginx.service > /dev/null 2>&1
systemctl enable systemd-readahead-collect.service > /dev/null 2>&1
systemctl enable systemd-readahead-drop.service > /dev/null 2>&1
systemctl enable systemd-readahead-replay.service > /dev/null 2>&1
systemctl enable xen-init-dom0.service > /dev/null 2>&1
systemctl enable xen-qemu-dom0-disk-backend.service > /dev/null 2>&1
systemctl enable xenconsoled.service > /dev/null 2>&1
systemctl enable xendomains.service > /dev/null 2>&1
systemctl enable dm-event.socket > /dev/null 2>&1
systemctl enable lvm2-lvmetad.socket > /dev/null 2>&1
systemctl enable lvm2-lvmpolld.socket > /dev/null 2>&1
systemctl enable default.target > /dev/null 2>&1
systemctl enable multi-user.target > /dev/null 2>&1
systemctl enable nrpe.service > /dev/null 2>&1
systemctl enable zabbix.service > /dev/null 2>&1

# Set hash-table size via /etc/rc.local
if [ `grep -ci hash-table /etc/rc.local` == "0" ]; then
  echo >> /etc/rc.local
  echo "# Set hash-table size (Should be conntrack_max \ 8)" >> /etc/rc.local
  echo "echo 49152 > /sys/module/nf_conntrack/parameters/hashsize" >> /etc/rc.local
  echo >> /etc/rc.local
fi

# Increase default loop devices via /etc/rc.local
if [ `grep -ci /dev/loop /etc/rc.local` == "0" ]; then
  echo >> /etc/rc.local
  echo "# Increase loop devices" >> /etc/rc.local
  echo "MAKEDEV -v /dev/loop" >> /etc/rc.local
  echo >> /etc/rc.local
fi

# Add custom sysctl entries
cat <<< "
# System default settings live in /usr/lib/sysctl.d/00-system.conf.
# To override those settings, enter new settings here, or in an /etc/sysctl.d/<name>.conf file
#
# For more information, see sysctl.conf(5) and sysctl.d(5).

# Controls IP packet forwarding
net.ipv4.ip_forward = 1

# Controls the use of TCP syncookies
net.ipv4.tcp_syncookies = 1

# Enable netfilter on bridges.
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1

# Controls the default maxmimum size of a mesage queue
kernel.msgmnb = 65536

# Controls the maximum size of a message, in bytes
kernel.msgmax = 65536

# Controls the maximum shared segment size, in bytes
kernel.shmmax = 68719476736

# Controls the maximum number of shared memory segments, in pages
kernel.shmall = 4294967296

# Increase number of connections for netfilter
net.nf_conntrack_max = 393216
" > /etc/sysctl.conf
chown root:root /etc/sysctl.conf
chmod 0644 /etc/sysctl.conf

# Install new xl.conf
cp -n /etc/xen/xl.conf /etc/xen/xl.conf.bak
cat <<< "
## Global XL config file ##

# Control whether dom0 is ballooned down when xen doesn't have enough
# free memory to create a domain.  \"auto\" means only balloon if dom0
# starts with all the host's memory.
autoballoon=\"off\"

# full path of the lockfile used by xl during domain creation
#lockfile=\"/var/lock/xl\"

# default output format used by \"xl list -l\"
#output_format=\"json\"

# first block device to be used for temporary VM disk mounts
#blkdev_start=\"xvda\"

# default option to run hotplug scripts from xl
# if disabled the old behaviour will be used, and hotplug scripts will be
# launched by udev.
#run_hotplug_scripts=1

# default backend domain to connect guest vifs to.  This can be any
# valid domain identifier.
#vif.default.backend=\"0\"

# default gateway device to use with vif-route hotplug script
#vif.default.gatewaydev=\"eth0\"

# default vif script to use if none is specified in the guest config
#vif.default.script=\"vif-bridge\"

# default bridge device to use with vif-bridge hotplug scripts
vif.default.bridge=\"xenbr0\"

# Reserve a claim of memory when launching a guest. This guarantees immediate
# feedback whether the guest can be launched due to memory exhaustion
# (which can take a long time to find out if launching huge guests).
# see xl.conf(5) for details.
#claim_mode=1
" > /etc/xen/xl.conf
chown root:root /etc/xen/xl.conf
chmod 0644 /etc/xen/xl.conf

# Install new config.ini
cp -n /usr/local/solusvm/data/config.ini /usr/local/solusvm/data/config.ini.bak > /dev/null 2>&1
cat <<< "
[XEN]
; Set this to true to remove the vifvm prefix from the interface vif names
no_vif_prefix = true
" > /usr/local/solusvm/data/config.ini
chown solusvm:solusvm /usr/local/solusvm/data/config.ini
chmod 0644 /usr/local/solusvm/data/config.ini

# Tell SolusVM we are using XL
touch /usr/local/solusvm/data/xl-toolstack

# Syncronise time with the hardware clock
systemctl stop ntpd.service > /dev/null 2>&1
ntpdate pool.ntp.org > /dev/null 2>&1
hwclock --systohc > /dev/null 2>&1
systemctl start ntpd.service > /dev/null 2>&1

# Check for users with shell access
if [ `grep bash /etc/passwd | wc -l` -ge "2" ]; then
  clear
  echo -e "\n WARNING - Multiple users found with shell access \n You should remove shell access from users when not required \n"
  grep bash /etc/passwd
  echo -e "\n We will continue in a few seconds. \n"
  sleep 10
fi

# (Optional) Restrict access to dangerous binaries
clear
echo -e "\n OPTIONAL - Restrict access to dangerous binaries \n Would you like to restrict wget and scp to root only? (Reccomended)"
echo -e "\n Option (y or n):"
read binprompt
if [ "$binprompt" == "y" ]; then
  chmod 750 /usr/bin/wget /usr/bin/scp
fi

# (Optional) Create a secure /tmp partition
if [ `df | awk '{ print $6 }' | grep -c /tmp` == "0" ]; then
  clear
  echo -e "\n OPTIONAL - Create a secure /tmp partition \n Would you like to create a 500MB /tmp partition with noexec,nosuid options? (Reccomended)"
  echo -e "\n Option (y or n):"
  read tmpprompt
  if [ "$tmpprompt" == "y" ]; then
    dd if=/dev/zero of=/securetmp bs=512 count=1000000
    mkfs.ext4 /securetmp
    echo "/securetmp		/tmp			ext4	loop,noexec,nosuid" >> /etc/fstab
    mount /tmp
    ln -s /tmp /var/tmp
    chmod 1777 /tmp /var/tmp
  fi
fi

# (Optional) CPU Affinity Management
clear
echo -e "\n OPTIONAL - CPU Affinity Management \n This will configure a script to run every 30 minutes, which ensures that \n Virtual CPU's (VCPUs) assigned to Virtual Machines, cannot be mapped to \n logical CPU's already mapped to Domain 0. (Reccomended)"
echo -e "\n Option (y or n):"
read cpuprompt
if [ "$cpuprompt" == "y" ]; then
  cat <<< "
#!/bin/bash
cpus=\`xl info | grep nr_cpus | awk '{ print \$3 }'\`
dcpu=\`nproc\`
for i in \`ls -1 /home/xen\`
do
  xl vcpu-pin \$i all \${dcpu}-\${cpus}
done
" > /etc/xen/xenaffinity.sh
  chmod 770 /etc/xen/xenaffinity.sh
  echo "*/30 * * * * root /etc/xen/xenaffinity.sh" > /etc/cron.d/xenaffinity
fi

# Completion message
clear
echo -e "\nFINISHED \n1. You must now create a network bridge called xenbr0 (Not br0 or anything else). \n Guide: https://documentation.solusvm.com/display/DOCS/KVM+Bridge+Setup \n"
echo -e '2. Edit /etc/default/grub and remove crashkernel=auto from the GRUB_CMDLINE_LINUX line. \n'
echo -e '3. Edit /etc/default/grub and add the required memory and VCPU options for Dom0. Below are some examples\n'
echo -e 'Upto 12GB RAM:\nGRUB_CMDLINE_XEN_DEFAULT="dom0_mem=1024M,max:1250M dom0_max_vcpus=1 dom0_vcpus_pin cpuinfo com1=115200,8n1 console=com1,tty"\n'
echo -e 'Upto 32GB RAM:\nGRUB_CMDLINE_XEN_DEFAULT="dom0_mem=2048M,max:2560M dom0_max_vcpus=2 dom0_vcpus_pin cpuinfo com1=115200,8n1 console=com1,tty"\n'
echo -e 'Upto 96GB RAM:\nGRUB_CMDLINE_XEN_DEFAULT="dom0_mem=3072M,max:4096M dom0_max_vcpus=4 dom0_vcpus_pin cpuinfo com1=115200,8n1 console=com1,tty"\n'

# END
