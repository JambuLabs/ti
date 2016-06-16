#!/bin/bash
# http://www.redmine.org/projects/redmine/wiki/RedmineInstall
# http://www.redmine.org/projects/redmine/wiki/EmailConfiguration
# http://www.redmine.org/projects/redmine/wiki/Install_Redmine_25x_on_Centos_65_complete

_URL_CENTRAL="http://prodigasistemas.github.io"
_REDMINE_VERSION="3.2.3"
_DEFAULT_PATH="/opt"
_REDMINE_FOLDER="$_DEFAULT_PATH/redmine"

_OPTIONS_LIST="install_redmine 'Install the Redmine $_REDMINE_VERSION in $_DEFAULT_PATH' \
               configure_database 'Configure connection to MySQL database' \
               configure_nginx 'Configure host on NGINX' \
               configure_email 'Configure sending email' \
               issue_reports_plugin 'Install Redmine issue reports plugin'"

_OPTIONS_DATABASE="database 'Create the user and redmine database' \
                   database.yml 'Configure the connection to the database'"

os_check () {
  _OS_ARCH=$(uname -m | sed 's/x86_//;s/i[3-6]86/32/')
  _OS_KERNEL=$(uname -r)

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

  _TITLE="--backtitle \"Redmine installation | OS: $_OS_DESCRIPTION | Kernel: $_OS_KERNEL\""
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

mysql_as_root () {
  mysql -h $1 -u root -p$2 -e "$3" 2> /dev/null
}

install_dependencies () {
  case $_OS_TYPE in
    deb)
      $_PACKAGES="libmagickwand-dev libgmp3-dev"
      ;;
    rpm)
      $_PACKAGES="ImageMagick-devel"

      #change_file replace /etc/selinux/config SELINUX=enforcing SELINUX=disabled
      ;;
  esac

  $_PACKAGE_COMMAND -y install $_PACKAGES
}

install_redmine () {
  if command -v ruby > /dev/null; then
    dialog --title 'Redmine install' --yesno "Confirm installation Redmine $_REDMINE_VERSION?" 0 0
    [ $? -eq 1 ] && main

    install_dependencies

    wget http://www.redmine.org/releases/redmine-$_REDMINE_VERSION.tar.gz

    tar -xvzf redmine-$_REDMINE_VERSION.tar.gz

    rm redmine-$_REDMINE_VERSION.tar.gz

    mv redmine-$_REDMINE_VERSION $_DEFAULT_PATH

    ln -sf $_DEFAULT_PATH/redmine-$_REDMINE_VERSION $_REDMINE_FOLDER

    echo "gem 'unicorn'" > $_REDMINE_FOLDER/Gemfile.local
    echo "gem 'holidays'" >> $_REDMINE_FOLDER/Gemfile.local

    cd $_REDMINE_FOLDER && bundle install --without development test --path $_REDMINE_FOLDER/vendor/bundle

    export RAILS_ENV=production

    cd $_REDMINE_FOLDER && REDMINE_LANG=pt-BR bundle exec rake redmine:load_default_data

    cd $_REDMINE_FOLDER && bundle exec rake generate_secret_token

    _UNICORN_RB_FILE=unicorn.rb
    curl -sS "$_URL_CENTRAL/scripts/templates/unicorn/unicorn.rb" > $_UNICORN_RB_FILE
    change_file replace $_UNICORN_RB_FILE __APP__ redmine
    change_file replace $_UNICORN_RB_FILE __PATH__ $_DEFAULT_PATH
    mv $_UNICORN_RB_FILE $_REDMINE_FOLDER/config
    rm $_UNICORN_RB_FILE*

    $_UNICORN_INIT_FILE=unicorn_init.sh
    curl -sS "$_URL_CENTRAL/scripts/templates/unicorn/unicorn_init.sh" > $_UNICORN_INIT_FILE
    change_file replace $_UNICORN_INIT_FILE __APP__ redmine
    change_file replace $_UNICORN_INIT_FILE __PATH__ $_DEFAULT_PATH
    chmod +x $_UNICORN_INIT_FILE
    mv $_UNICORN_INIT_FILE $_REDMINE_FOLDER/config
    rm $_UNICORN_INIT_FILE*
    ln -sf $_REDMINE_FOLDER/config/$_UNICORN_INIT_FILE /etc/init.d/unicorn_redmine
    update-rc.d unicorn_redmine defaults
    /etc/init.d/unicorn_redmine start

    message "Notice" "Redmine successfully installed!"
  else
    message "Alert" "Ruby language is not installed!"
  fi
}

configure_database () {
  _OPTION=$(menu "Select which configuration" "$_OPTIONS_DATABASE")
  [ -z "$_OPTION" ] && main

  case $_OPTION in
    database)
      if command -v mysql > /dev/null; then
        _HOST_ADDRESS=$(input "Enter the host address of the MySQL Server" "localhost")
        [ $? -eq 1 ] && main
        [ -z "$_HOST_ADDRESS" ] && message "Alert" "The host address can not be blank!"
      else
        message "Alert" "MySQL Client is not installed!"
      fi

      _MYSQL_ROOT_PASSWORD=$(input "Enter the password of the root user in MySQL")
      [ $? -eq 1 ] && main
      [ -z "$_MYSQL_ROOT_PASSWORD" ] && message "Alert" "The root password can not be blank!"

      _MYSQL_REDMINE_PASSWORD=$(input "Enter the password of the redmine user in MySQL")
      [ $? -eq 1 ] && main
      [ -z "$_MYSQL_REDMINE_PASSWORD" ] && message "Alert" "The redmine password can not be blank!"

      mysql_as_root $_HOST_ADDRESS $_MYSQL_ROOT_PASSWORD "CREATE DATABASE IF NOT EXISTS redmine CHARACTER SET utf8;"
      mysql_as_root $_HOST_ADDRESS $_MYSQL_ROOT_PASSWORD "CREATE USER redmine@$_HOST_CONNECTION IDENTIFIED BY '$_MYSQL_REDMINE_PASSWORD';"
      mysql_as_root $_HOST_ADDRESS $_MYSQL_ROOT_PASSWORD "GRANT ALL PRIVILEGES ON redmine.* TO redmine@$_HOST_CONNECTION WITH GRANT OPTION; FLUSH PRIVILEGES;"

      message "Notice" "User and database redmine successfully created!"
      ;;

    database.yml)
      _YAML_FILE="$_REDMINE_FOLDER/config/database.yml"

      _HOST_ADDRESS=$(input "Enter the host address of the MySQL Server" "localhost")
      [ $? -eq 1 ] && main
      [ -z "$_HOST_ADDRESS" ] && message "Alert" "The host address can not be blank!"

      _MYSQL_REDMINE_PASSWORD=$(input "Enter the password of the redmine user in MySQL")
      [ $? -eq 1 ] && main
      [ -z "$_MYSQL_REDMINE_PASSWORD" ] && message "Alert" "The redmine password can not be blank!"

      echo "production:" > $_YAML_FILE
      echo "  adapter: mysql2" >> $_YAML_FILE
      echo "  database: redmine" >> $_YAML_FILE
      echo "  host: $_HOST_ADDRESS" >> $_YAML_FILE
      echo "  username: redmine" >> $_YAML_FILE
      echo "  password: \"$_MYSQL_REDMINE_PASSWORD\"" >> $_YAML_FILE
      echo "  encoding: utf8" >> $_YAML_FILE

      cd $_REDMINE_FOLDER && RAILS_ENV=production bundle exec rake db:migrate

      message "Notice" "Connection to the database configured!"
      ;;
  esac
}

configure_nginx () {
  if command -v nginx > /dev/null; then
    _DOMAIN=$(input "Enter the domain of Redmine" "redmine.company.gov")
    [ $? -eq 1 ] && main
    [ -z "$_DOMAIN" ] && message "Alert" "The domain can not be blank!"

    curl -sS "$_URL_CENTRAL/scripts/templates/nginx/ruby_on_rails.conf" > redmine.conf

    change_file replace redmine.conf APP "redmine"
    change_file replace redmine.conf DOMAIN "$_DOMAIN"
    change_file replace redmine.conf PATH "$_DEFAULT_PATH"

    mv redmine.conf /etc/nginx/conf.d/
    rm redmine.conf*

    service nginx restart

    message "Notice" "The host is successfully configured in NGINX!"
  else
    message "Alert" "NGINX is not installed!"
  fi
}

configure_email () {
  _DOMAIN=$(input "Enter the domain" "company.com")
  [ $? -eq 1 ] && main
  [ -z "$_DOMAIN" ] && message "Alert" "The domain can not be blank!"

  _SMTP_ADDRESS=$(input "Enter the SMTP address" "smtp.$_DOMAIN")
  [ $? -eq 1 ] && main
  [ -z "$_SMTP_ADDRESS" ] && message "Alert" "The SMTP address can not be blank!"

  _USER_NAME=$(input "Enter the user name")
  [ $? -eq 1 ] && main
  [ -z "$_USER_NAME" ] && message "Alert" "The user name can not be blank!"

  _USER_PASSWORD=$(input "Enter the user password")
  [ $? -eq 1 ] && main
  [ -z "$_USER_PASSWORD" ] && message "Alert" "The user password can not be blank!"

  dialog --title 'Configure sending email' --yesno "Domain: $_DOMAIN\nSMTP: $_SMTP_ADDRESS\nUser: $_USER_NAME\nPassword: $_USER_PASSWORD\nConfirm?" 0 0
  [ $? -eq 1 ] && main

  $_CONFIG_FILE=$_REDMINE_FOLDER/config/configuration.yml

  echo "production:" > $_CONFIG_FILE
  echo "email_delivery:" >> $_CONFIG_FILE
  echo "  delivery_method: :smtp" >> $_CONFIG_FILE
  echo "  smtp_settings:" >> $_CONFIG_FILE
  echo "    address: \"$_SMTP_ADDRESS\"" >> $_CONFIG_FILE
  echo "    port: 25" >> $_CONFIG_FILE
  echo "    authentication: :login" >> $_CONFIG_FILE
  echo "    domain: '$_DOMAIN'" >> $_CONFIG_FILE
  echo "    user_name: '$_USER_NAME'" >> $_CONFIG_FILE
  echo "    password: '$_USER_PASSWORD'" >> $_CONFIG_FILE

  /etc/init.d/unicorn_redmine upgrade

  message "Notice" "Sending email is successfully configured!"
}

issue_reports_plugin () {
  _ISSUE_REPORTS_FOLDER=$_REDMINE_FOLDER/plugins/redmine_issue_reports

  if command -v mysql > /dev/null; then
    _HOST=$(input "Enter the host address of database" "localhost")
    [ $? -eq 1 ] && main
    [ -z "$_HOST" ] && message "Alert" "The host address can not be blank!"

    _USER_PASSWORD=$(input "Enter the redmine password in database")
    [ $? -eq 1 ] && main
    [ -z "$_USER_PASSWORD" ] && message "Alert" "The redmine password can not be blank!"

    wget https://github.com/prodigasistemas/redmine_issue_reports/archive/master.zip

    unzip master.zip
    rm master.zip
    mv redmine_issue_reports-master $_ISSUE_REPORTS_FOLDER

    cp $_ISSUE_REPORTS_FOLDER/config/config.example.yml $_ISSUE_REPORTS_FOLDER/config/config.yml
    cp $_ISSUE_REPORTS_FOLDER/update-redmine/custom_fields.js $_REDMINE_FOLDER/public/javascripts

    _ISSUE_FORM_FILE=$_REDMINE_FOLDER/app/views/issues/_form.html.erb
    _FIND_TAG=$(cat $_ISSUE_FORM_FILE | grep custom_fields)

    [ -z "$_FIND_TAG" ] && echo "<%= javascript_include_tag 'custom_fields' %>" >> $_ISSUE_FORM_FILE

    mysql -h $_HOST -u redmine -p$_USER_PASSWORD redmine < $_ISSUE_REPORTS_FOLDER/update-redmine/redmine_config.sql

    message "Notice" "Issue reports plugin is successfully configured!"
  else
    message "Alert" "The mysql-client is not installed!"
  fi
}

main () {
  tool_check curl
  tool_check unzip
  tool_check wget
  tool_check dialog

  _MAIN_OPTION=$(menu "Select the option" "$_OPTIONS_LIST")

  if [ -z "$_MAIN_OPTION" ]; then
    clear && exit 0
  else
    $_MAIN_OPTION
  fi
}

os_check
main