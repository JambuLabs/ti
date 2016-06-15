#!/bin/bash

# http://www.oracle.com/technetwork/database/database-technologies/express-edition/overview/index.html
# https://hub.docker.com/r/wnameless/oracle-xe-11g/
# http://www.orafaq.com/wiki/NLS_LANG
# http://stackoverflow.com/questions/19335444/how-to-assign-a-port-mapping-to-an-existing-docker-container

_OPTIONS_LIST="install_oracleb 'Install Oracle Database 11g Express Edition with Docker' \
               import_ggas_database 'Import GGAS Database'"

os_check () {
  _OS_ARCH=$(uname -m | sed 's/x86_//;s/i[3-6]86/32/')

  if [ $(which lsb_release 2>/dev/null) ]; then
    _OS_TYPE="deb"
    _OS_NAME=$(lsb_release -is | awk '{ print tolower($1) }')
    _OS_CODENAME=$(lsb_release -cs)
    _OS_DESCRIPTION="$(lsb_release -cds) $_OS_ARCH bits"
    _PACKAGE_COMMAND="apt-get"
  elif [ -e "/etc/redhat-release" ]; then
    _OS_TYPE="rpm"
    _OS_NAME=$(cat /etc/redhat-release | awk '{ print tolower($1) }')
    _OS_RELEASE=$(cat /etc/redhat-release | awk '{ print tolower($3) }' | cut -d. -f1)
    _OS_DESCRIPTION="$(cat /etc/redhat-release) $_OS_ARCH bits"
    _PACKAGE_COMMAND="yum"
  fi

  _TITLE="--backtitle \"Oracle Database installation - OS: $_OS_DESCRIPTION\""
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

menu () {
  echo $(eval dialog $_TITLE --stdout --menu \"$1\" 0 0 0 $2)
}

input () {
  echo $(eval dialog $_TITLE --stdout --inputbox \"$1\" 0 0 \"$2\")
}

message () {
  eval dialog --title \"$1\" --msgbox \"$2\" 0 0
  main
}

change_file () {
  _CF_BACKUP=".backup-`date +"%Y%m%d%H%M%S%N"`"
  _CF_OPERATION=$1
  _CF_FILE=$2
  _CF_FROM=$3
  _CF_TO=$4

  case $_CF_OPERATION in
    replace)
      sed -i$_CF_BACKUP -e "s/$_CF_FROM/$_CF_TO/g" $_CF_FILE
      ;;
    append)
      sed -i$_CF_BACKUP -e "/$_CF_FROM/ a $_CF_TO" $_CF_FILE
      ;;
  esac
}

run_as_root () {
  su -c "$1"
}

install_oracleb () {
  _SSH_PORT=$(input "Inform the ssh port (22) to be exported" "2222")
  [ $? -eq 1 ] && main
  [ -z "$_SSH_PORT" ] && message "Alert" "The ssh port can not be blank!"

  _CONECTION_PORT=$(input "Inform the connection port (1521) to be exported" "1521")
  [ $? -eq 1 ] && main
  [ -z "$_CONECTION_PORT" ] && message "Alert" "The connection port can not be blank!"

  _HTTP_PORT=$(input "Inform the http port (8080) to be exported" "5050")
  [ $? -eq 1 ] && main
  [ -z "$_HTTP_PORT" ] && message "Alert" "The http port can not be blank!"

  dialog --yesno "Confirm the installation of Oracle Database in $_OS_DESCRIPTION?" 0 0
  [ $? -eq 1 ] && main

  docker run --name oracle-xe-11g -d -p $_SSH_PORT:22 -p $_CONECTION_PORT:1521 -p $_HTTP_PORT:8080 --restart="always" wnameless/oracle-xe-11g

  message "Notice" "Oracle Database successfully installed!"
}

import_ggas_database () {
  dialog --yesno "Confirms the import of GGAS database?" 0 0
  [ $? -eq 1 ] && main

  [ -e "ggas" ] && rm -rf ggas

  echo
  echo "=================================================="
  echo "Cloning repo from http://ggas.com.br/root/ggas.git"
  echo "=================================================="
  git clone http://ggas.com.br/root/ggas.git

  _SEARCH_STRING="CREATE OR REPLACE FUNCTION \"GGAS_ADMIN\".\"SQUIRREL_GET_ERROR_OFFSET\""
  change_file replace ggas/sql/GGAS_SCRIPT_INICIAL_ORACLE_02_ESTRUTURA_CONSTRAINTS_CARGA_INICIAL.sql "$_SEARCH_STRING" "-- $_SEARCH_STRING"

  for i in ggas/sql/*.sql ; do echo " " >> $i ; done
  for i in ggas/sql/*.sql ; do echo "exit;" >> $i ; done

  mkdir ggas/sql/01 ggas/sql/02

  mv ggas/sql/GGAS_SCRIPT_INICIAL_ORACLE_0*.sql ggas/sql/01/
  mv ggas/sql/*.sql ggas/sql/02/

  _IMPORT_SCRIPT="ggas/sql/import_db.sh"
  echo '#!/bin/bash' > $_IMPORT_SCRIPT
  echo 'export NLS_LANG=AMERICAN_AMERICA.AL32UTF8' >> $_IMPORT_SCRIPT
  echo 'export PATH=$PATH:/u01/app/oracle/product/11.2.0/xe/bin' >> $_IMPORT_SCRIPT
  echo 'export ORACLE_HOME=/u01/app/oracle/product/11.2.0/xe' >> $_IMPORT_SCRIPT
  echo 'export ORACLE_SID=XE' >> $_IMPORT_SCRIPT
  echo 'for i in /tmp/sql/01/*.sql ; do echo "> Importando o arquivo $i ..." ; sqlplus system/oracle @$i ; done' >> $_IMPORT_SCRIPT
  echo 'for i in /tmp/sql/02/*.sql ; do echo "> Importando o arquivo $i ..." ; sqlplus GGAS_ADMIN/GGAS_ADMIN @$i ; done' >> $_IMPORT_SCRIPT
  chmod +x $_IMPORT_SCRIPT

  echo
  echo "===================================================="
  echo "you must run the commands in the container oracle db"
  echo "The root password is 'admin'"
  echo "===================================================="

  echo
  echo "====================================="
  echo "Copy sql files to container oracle db"
  echo "====================================="
  scp -P 2222 -r ggas/sql root@localhost:/tmp

  echo
  echo "======================================="
  echo "Import sql files to container oracle db"
  echo "======================================="
  ssh -p 2222 root@localhost "/tmp/sql/import_db.sh"

  message "Notice" "Import GGAS database was successful!"
}

main () {
  tool_check dialog
  tool_check git

  if [ $_OS_ARCH = "32" ]; then
    dialog --title "Alert" --msgbox "Oracle Database requires a 64-bit installation regardless of your distribution version!" 0 0
    clear && exit 0
  fi

  if command -v docker > /dev/null; then
    _OPTION=$(menu "Select the option" "$_OPTIONS_LIST")

    if [ -z "$_OPTION" ]; then
      clear && exit 0
    else
      $_OPTION
    fi
  else
    dialog --title "Alert" --msgbox "Docker is not installed" 0 0
    clear && exit 0
  fi
}

os_check
main
