#!/bin/bash
# https://rvm.io/rvm/install
# https://www.ruby-lang.org/en/downloads

_DEFAULT_USER="$USER"
_DEFAULT_VERSION="2.3.1"
_PACKAGE_COMMAND_DEBIAN="apt-get"
_PACKAGE_COMMAND_CENTOS="yum"

os_check () {
  if [ $(which lsb_release 2>/dev/null) ]; then
    _OS_NAME=$(lsb_release -i | cut -f2 | awk '{ print tolower($1) }')
    _PACKAGE_COMMAND=$_PACKAGE_COMMAND_DEBIAN
  elif [ -e "/etc/redhat-release" ]; then
    _OS_NAME=$(cat /etc/redhat-release | awk '{ print tolower($1) }')
    _PACKAGE_COMMAND=$_PACKAGE_COMMAND_CENTOS
  fi

  _TITLE="--backtitle \"Ruby installation - OS: $_OS_NAME\""
}

tool_check() {
  echo "Checking for $1..."
  if command -v $1 > /dev/null; then
    echo "Detected $1..."
  else
    echo "Installing $1..."
    $_PACKAGE_COMMAND install -y $1
  fi
}

input () {
  echo $(eval dialog $_TITLE --stdout --inputbox \"$1\" 0 0 \"$2\")
}

message () {
  eval dialog --title \"$1\" --msgbox \"$2\" 0 0
}

install_ruby () {
  _VERSION=$(input "Ruby version" $_DEFAULT_VERSION)
  [ -z "$_VERSION" ] && _VERSION=$_DEFAULT_VERSION

  _USER=$(input "User to be added to the group rvm" $_DEFAULT_USER)
  [ -z "$_USER" ] && _USER=$_DEFAULT_USER

  dialog --yesno "Do you confirm the installation of Ruby $_VERSION?" 0 0
  [ $? = 1 ] && exit 0

  gpg --keyserver hkp://keys.gnupg.net --recv-keys 409B6B1796C275462A1703113804BB82D39DC0E3

  curl -sSL https://get.rvm.io | bash -s stable

  source /etc/profile.d/rvm.sh

  usermod -a -G rvm $_USER

  rvmsudo rvm install $_VERSION

  rvmsudo rvm alias create default $_VERSION

  echo "gem: --no-rdoc --no-ri" | tee /etc/gemrc

  gem install bundler

  message "Notice" "Success! Enter the command: rvm -v. If not found, log out and log back. After, execute: gem install bundler"

  clear
}

main () {
  tool_check curl
  tool_check dialog

  install_ruby
}

os_check
main
