#!/bin/bash
# Filename...: md5-index.sh
# Description: MD5 based directory integrity monitoring /w exclusion support
# Chris Elliott -- https://github.com/c-elliott

# Email Settings (mailx/mail binary must be in $PATH)
EMAIL="email@address.com"          # Comment out to disable email alerts

  ############# DO NOT EDIT BELOW THIS LINE #############

# Check we are root
if [ `whoami` != "root" ]; then
  echo "ERROR. I must be run as root."
  exit 0
fi

# Check we have a conf file, if not create it
if [ ! -f /etc/md5-index.conf ]; then
  echo "/etc/md5-index.conf does not exist. Created new file."
  touch /etc/md5-index.conf
  if [ ! -f /etc/md5-index.conf ]; then
    echo "ERROR! Cannot create file: /etc/md5-index.conf"
    exit 0
  fi
fi

# List all monitored directories
if [ "$1" = "-l" ] || [ "$1" = "--list" ]; then
  echo -e "Directory Exclusions\n`cat /etc/md5-index.conf`" | tr : " " | column -t

# Reset / Clear configuration and indexes
elif [ "$1" = "-r" ] || [ "$1" = "--reset" ]; then
  echo "Are you sure you want to clear configuration and indexes?: "
  read CHECK
  if [ "$CHECK" = "y" ]; then
    cat /etc/md5-index.conf > /etc/md5-index.conf.bak
    > /etc/md5-index.conf
    rm -f /tmp/md5-index-*
    echo "Directory list reset. Backup created /etc/md5-index.bak"
  fi

# Add new directory to be monitored
elif [ "$1" = "-a" ] || [ "$1" = "--add" ]; then
  echo "Enter directory with any exclusions delimited with a :"
  echo
  echo " Example 1: /home/user/www (No exclusions)"
  echo " Example 2: /home/user/www:files/one (Exclude \"files/one\" directory)"
  echo
  echo "Enter directory: "
  read INPUTDIR
  if [ ! -z "$INPUTDIR" ]; then
    DIRECTORY=`echo $INPUTDIR | cut -d : -f1`
    if [ `grep -c $DIRECTORY /etc/md5-index.conf` = "0" ]; then
      echo $INPUTDIR >> /etc/md5-index.conf
      echo
      echo "Added new monitored directory: $INPUTDIR"
      echo "You should now update the indexes and check."
    else
      echo
      echo "Entry already exists for: $INPUTDIR"
    fi
  else
    echo
    echo "Error. I need a valid path"
  fi

# Check monitored directories
elif [ "$1" = "-c" ] || [ "$1" = "--check" ]; then
  INDEX="1"
  echo "Checking indexes."
  for INDEXDIR in `cat /etc/md5-index.conf | cut -d : -f1`; do
    find $INDEXDIR -type f -exec md5sum {} \; > /tmp/md5-index-${INDEX}.tmp 2>/dev/null
    for EXCLUDE in `grep $INDEXDIR /etc/md5-index.conf | cut -d : -f 2- | tr ":" "\n"`; do
      grep -v "$EXCLUDE" /tmp/md5-index-${INDEX}.tmp > /tmp/md5-index-${INDEX}.tmp2
      mv -f /tmp/md5-index-${INDEX}.tmp2 /tmp/md5-index-${INDEX}.tmp
    done
    INDEXCHK=`diff /tmp/md5-index-${INDEX}.md5 /tmp/md5-index-${INDEX}.tmp`
    INDEXRES=`echo $INDEXCHK | grep -c '<\|>'`
    if [ "$INDEXRES" = "0" ]; then
      echo "OK. No change detected on $INDEXDIR"
    else
      echo $INDEXCHK > /tmp/md5-index-${INDEX}.diff
      echo "WARNING! Change detected on ${INDEXDIR}. See /tmp/md5-index-${INDEX}.diff"
      if [ ! -z "$EMAIL" ]; then
        echo "Mail sent to $EMAIL"
        echo -e "Potentially unauthorized changes have been detected on $HOSTNAME and should be investigated immediatley.\n\nMonitored Directory: $INDEXDIR\nCurrent Date: `date`\nSystem Uptime: `uptime`\n\nDIFF:\n=====\n`cat /tmp/md5-index-${INDEX}.diff`" | mail -s "md5-index Detected change on $HOSTNAME" $EMAIL
      fi
    fi
    ((INDEX++))
  done

# Update indexes
elif [ "$1" = "-u" ] || [ "$1" = "--update" ]; then
  INDEX="1"
  for INDEXDIR in `cat /etc/md5-index.conf | cut -d : -f1`; do
    echo "Rebuilding index for: $INDEXDIR"
    find $INDEXDIR -type f -exec md5sum {} \; > /tmp/md5-index-${INDEX}.md5 2>/dev/null
    for EXCLUDE in `grep $INDEXDIR /etc/md5-index.conf | cut -d : -f 2- | tr ":" "\n"`; do
      grep -v "$EXCLUDE" /tmp/md5-index-${INDEX}.md5 > /tmp/md5-index-${INDEX}.tmp
      mv -f /tmp/md5-index-${INDEX}.tmp /tmp/md5-index-${INDEX}.md5
  done
    ((INDEX++))
  done
  echo "Directory indexes updated."

# Provide syntax help if we recieve undefined or null argument
else
  echo "md5-index.sh : https://github.com/c-elliott"
  echo "-------------------------------------------"
  echo "Syntax: $basename $0 <option>"
  echo "  -l  --list    List all monitored directories."
  echo "  -r  --reset   Clear configuration and indexes."
  echo "  -a  --add     Add a new directory to be monitored."
  echo "  -u  --update  Update directory indexes."
  echo "  -c  --check   Check monitored directories."
fi
