#!/bin/bash
# Filename...: jtr.sh
# Description: Simple frontend for john the ripper
# Chris Elliott -- https://github.com/c-elliott

# Download Source
JOHNSRC="http://www.openwall.com/john/j/john-1.8.0.tar.xz"

# Don't edit below this line
if [ ! -z "$1" ] && [ "$1" = "install" ]; then
  if [ -e ~/john-*/run/john ]; then
    echo "John is already installed"
  else
    yum install -y make gcc
    cd ~
    wget $JOHNSRC
    tar xf john-*.tar.xz
    cd john-*/src
    make clean linux-x86-64
    cd ~
    rm -f john-*.tar.xz
  fi
elif [ ! -z "$1" ] && [ "$1" = "test" ]; then
  john-*/run/john --test
elif [ ! -z "$1" ] && [ "$1" = "local" ]; then
  john-*/run/unshadow /etc/passwd /etc/shadow > ~/jtr-config.txt
  echo "Created file ~/jtr-config.txt using unshadow."
  echo "To execute now: ./jtr.sh run ~/jtr-config.txt"
elif [ ! -z "$1" ] && [ "$1" = "run" ] && [ -z "$2" ]; then
  echo "This will max out all CPU cores on this system. Are you sure?"
  echo "Option (y/n):"
  read PROMPT
  if [ "$PROMPT" = "y" ]; then
    john-*/run/john $2 --fork=`grep -c ^processor /proc/cpuinfo`
  else
  echo "Quit on user request."
  fi
elif [ ! -z "$1" ] && [ "$1" = "run" ] && [ ! -z "$2" ]; then
  echo "I need something to test. Example: ./jtr.sh run ~/jtr-config.txt"
else
  echo "Syntax: ./jtr.sh <option>"
  echo "  install  = Download, compile and install in home directory."
  echo "  test     = Test to see if things are working."
  echo "  local    = Create config file based on local passwd/shadow."
  echo "  run      = Run an existing configuration file."
  echo
fi
