#!/bin/bash
set -xeu
set -o pipefail

create_systemd_unit() {
    SERVICE_NAME="$1"
    USER="$2"
    GROUP="$2"
    START_COMMAND="$3"
    cat > /etc/systemd/system/"$SERVICE_NAME".service << EOF
[Unit]
Description=$SERVICE_NAME
Wants=network-online.target
After=network-online.target

[Service]
User=$USER
Group=$GROUP
Type=simple
ExecStart=$START_COMMAND

[Install]
WantedBy=multi-user.target
EOF
    reload_daemon
}

reload_daemon() {
    systemctl daemon-reload
}

enable_services() {
    systemctl enable "$@"
}

start_services() {
    systemctl start "$@"
}

stop_services() {
    systemctl stop "$@"
}

restart_services() {
    stop_services "$@"
    start_services "$@"
}

generate_certificates() {
  export CERT_PATH=$(pwd)

  common_name="$1"

  subj="/C=US/ST=California/L=Sunnyvale/O=Mirantis Inc./OU=IT Department/CN=$common_name.devenv.mirantis.net"

  # Create clean environment
  dirname="$common_name"_certs
  rm -rf "$dirname"
  mkdir -p "$dirname" && pushd "$dirname"

  # Create CA certificate
  openssl genrsa 2048 > ca-"$common_name"-key.pem
  openssl req -new -x509 -nodes -days 3600 \
  -key ca-"$common_name"-key.pem -out ca-"$common_name".pem -subj "$subj"

  # Create server certificate, remove passphrase, and sign it
  # server-cert.pem = public key, server-key.pem = private key
  openssl req -newkey rsa:2048 -days 3600 \
          -nodes -keyout server-"$common_name"-key.pem -out server-"$common_name"-req.pem -subj "$subj"
  openssl rsa -in server-"$common_name"-key.pem -out server-"$common_name"-key.pem
  openssl x509 -req -in server-"$common_name"-req.pem -days 3600 \
          -CA ca-"$common_name".pem -CAkey ca-"$common_name"-key.pem -set_serial 01 -out server-"$common_name"-cert.pem
  # Create client certificate, remove passphrase, and sign it
  # client-cert.pem = public key, client-key.pem = private key
  openssl req -newkey rsa:2048 -days 3600 \
          -nodes -keyout client-"$common_name"-key.pem -out client-"$common_name"-req.pem -subj "$subj"
  openssl rsa -in client-"$common_name"-key.pem -out client-"$common_name"-key.pem
  openssl x509 -req -in client-"$common_name"-req.pem -days 3600 \
          -CA ca-"$common_name".pem -CAkey ca-"$common_name"-key.pem -set_serial 01 -out client-"$common_name"-cert.pem

  popd
}

add_elasticsearch_repo() {
    wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -
    echo "deb https://artifacts.elastic.co/packages/5.x/apt stable main" > /etc/apt/sources.list.d/elastic-5.x.list
}

generate_prometheus_config() {
    cat > /etc/prometheus/prometheus.yml <<EOF
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: 'prometheus'
    scrape_interval: 5s
    static_configs:
      - targets: ['localhost:9090']
  - job_name: 'node_exporter'
    scrape_interval: 5s
    static_configs:
      - targets: ['localhost:9100']
EOF
}

setup_prometheus() {
    useradd --no-create-home --shell /bin/false prometheus || echo "User prometheus already exist"
    useradd --no-create-home --shell /bin/false node_exporter || echo "User node_exporter already exist"
    mkdir -p /etc/prometheus
    mkdir -p /var/lib/prometheus

    # Generate config
    generate_prometheus_config

    # Download Prometheus v2.0
    wget https://github.com/prometheus/prometheus/releases/download/v2.0.0/prometheus-2.0.0.linux-amd64.tar.gz
    tar -xvf prometheus-2.0.0.linux-amd64.tar.gz
    cp prometheus-2.0.0.linux-amd64/prometheus /usr/local/bin/
    cp prometheus-2.0.0.linux-amd64/promtool /usr/local/bin/
    cp -r prometheus-2.0.0.linux-amd64/consoles /etc/prometheus
    cp -r prometheus-2.0.0.linux-amd64/console_libraries /etc/prometheus

    chown -R prometheus:prometheus /usr/local/bin/prometheus /usr/local/bin/promtool /etc/prometheus/consoles /etc/prometheus/console_libraries /var/lib/prometheus

    # Download Node Exporter
    wget https://github.com/prometheus/node_exporter/releases/download/v0.15.1/node_exporter-0.15.1.linux-amd64.tar.gz
    tar -xvf node_exporter-0.15.1.linux-amd64.tar.gz
    cp node_exporter-0.15.1.linux-amd64/node_exporter /usr/local/bin

    chown node_exporter:node_exporter /usr/local/bin/node_exporter

    create_systemd_unit prometheus prometheus "/usr/local/bin/prometheus --config.file /etc/prometheus/prometheus.yml --storage.tsdb.path /var/lib/prometheus/ --web.console.templates=/etc/prometheus/consoles --web.console.libraries=/etc/prometheus/console_libraries"
    create_systemd_unit node_exporter node_exporter "/usr/local/bin/node_exporter"

    enable_services prometheus node_exporter
    start_services prometheus node_exporter

    # Remove unnecessary files
    rm -rf prometheus-2.0.0.linux-amd64.tar.gz prometheus-2.0.0.linux-amd64 node_exporter-0.15.1.linux-amd64.tar.gz node_exporter-0.15.1.linux-amd64
}

install_packages() {
    apt-get update
    DEBIAN_FRONTEND="noninteractive" apt-get install -y "$@"
}

download_zip_and_extract() {
    URL="$1"
    NAME="$2"
    wget -O "$NAME".zip "$URL"
    unzip "$NAME".zip
    mv "$NAME" /usr/local/bin
    rm -rf "$NAME".zip
}

setup_consul() {
    download_zip_and_extract "https://releases.hashicorp.com/consul/1.0.3/consul_1.0.3_linux_amd64.zip" consul
    create_systemd_unit consul-dev root "/usr/local/bin/consul agent -dev -ui -client 0.0.0.0 -bind 0.0.0.0"

    enable_services consul-dev
    start_services consul-dev
}

setup_vault() {
    download_zip_and_extract "https://releases.hashicorp.com/vault/0.9.3/vault_0.9.3_linux_amd64.zip" vault
    create_systemd_unit vault-dev root "/usr/local/bin/vault server -config /etc/vault/config.hcl"

    mkdir -p vault-config && pushd vault-config
    cat > policies.hcl <<EOF
path "*" {
capabilities = ["create", "read", "update", "delete", "list"]
}
EOF
    popd
    mkdir -p /etc/vault
    cat > /etc/vault/config.hcl <<EOF
storage "consul" {
  address = "127.0.0.1:8500"
  path    = "vault"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = 0
  tls_cert_file = "$CERT_PATH/vault_certs/server-vault-cert.pem"
  tls_key_file = "$CERT_PATH/vault_certs/server-vault-key.pem"
}
EOF

    enable_services vault-dev
    start_services vault-dev
    # Unseal vault
    export VAULT_SKIP_VERIFY=true

    output=$(vault operator init | grep -v "^$")
    root_token=$(echo "$output" | grep "Root Token" | awk '{ print $NF }')
    # Black magic that trim .[0m
    root_token=${root_token:0:${#root_token} - 4}
    keys=$(echo "$output" | grep "Unseal Key" | awk '{ print $NF }')
    export VAULT_TOKEN="$root_token"
    for key in $keys; do
      # Black magic that trim .[0m
      key=${key:0:${#key} - 4}
      vault operator unseal "$key"
    done
    vault policy write allow-all $CERT_PATH/vault-config/policies.hcl
    vault auth enable cert
    vault write auth/cert/certs/saas display_name=saas policies=allow-all,admin certificate=@"$CERT_PATH"/vault_certs/server-vault-cert.pem ttl=0
    # unset VAULT_TOKEN
    unset VAULT_SKIP_VERIFY
}

setup_apache() {
    sed -i "s/*:80/IP_ADDRESS:8080/g" /etc/apache2/sites-enabled/000-default.conf
    sed -i "s/Listen 80/Listen $IP_ADDRESS:8080/g" /etc/apache2/ports.conf
    restart_services apache2
}

setup_varnish() {
    sed -i "s/127.0.0.1/$IP_ADDRESS/g" /etc/varnish/default.vcl
    mkdir -p /etc/systemd/system/varnish.service.d
    cat > /etc/systemd/system/varnish.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=/usr/sbin/varnishd -j unix,user=vcache -F -a :80 -T localhost:6082 -f /etc/varnish/default.vcl -S /etc/varnish/secret -s malloc,1024m
EOF
    reload_daemon
    start_services varnish
}

check_services() {
    for service in "${!SERVICES_MAP[@]}"; do
        NAME="$service"
        PORT="${SERVICES_MAP[$service]}"
        netstat_res=$(netstat -tulpan | grep -c "$PORT")
        systemctl_status=$(systemctl status "$NAME" | grep -c "active")
        if [[ "$netstat_res" -ge 1 ]] && [[ "$systemctl_status" -ge 1 ]] ; then
            echo "$NAME running on $PORT"
        else
            exit 1
        fi
    done
}

show_services_table() {
   set +x
   echo "+--------------------+--------------------+"
   echo "| Service name       | Port               |"
   echo "+--------------------+--------------------+"
   for service in "${!SERVICES_MAP[@]}"; do
       NAME="$service"
       PORT="${SERVICES_MAP[$service]}"
       printf "| %-19s| %-19s|\n" "$NAME" "$PORT"
       echo "+--------------------+--------------------+"
   done
   printf "| %-19s| %-19s|\n" "VAULT ROOT TOKEN" "$VAULT_TOKEN"
   echo "+--------------------+--------------------+"
}

expose_ports() {
    # Expose elasticsearch
    echo "network.host: 0.0.0.0" >> /etc/elasticsearch/elasticsearch.yml
    # Expose postgres
    sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/g" /etc/postgresql/9.5/main/postgresql.conf
    echo "host all all all md5" >> /etc/postgresql/9.5/main/pg_hba.conf
    # Create dev-user with password
    sudo -u postgres bash -c "psql -c \"CREATE USER dev WITH PASSWORD 'password';\"" || echo "User dev already exists"

    # Expose mysql
    sed -i "s/127.0.0.1/0.0.0.0/g" /etc/mysql/mysql.conf.d/mysqld.cnf

    restart_services elasticsearch postgresql mysql
}

add_debconf_selection() {
  debconf-set-selections <<< "$1"
}

setup_mysql() {
  chown -R mysql:mysql $CERT_PATH/mysql_certs

  for str in  ssl-ca=$CERT_PATH/mysql_certs/ca-mysql.pem ssl-cert=$CERT_PATH/mysql_certs/server-mysql-cert.pem ssl-key=$CERT_PATH/mysql_certs/server-mysql-key.pem ; do
    if [[ $(grep ^$(echo $str | awk -F '=' '{print $1}') /etc/mysql/mysql.conf.d/mysqld.cnf | wc -l) -eq 0 ]] ; then
      echo $str >> /etc/mysql/mysql.conf.d/mysqld.cnf
    fi
  done

  mysql -prootpw -e "CREATE USER 'dev'@'%' REQUIRE ISSUER '/C=US/ST=California/L=Sunnyvale/O=Mirantis Inc./OU=IT Department/CN=mysql.devenv.mirantis.net'"
  mysql -prootpw -e "GRANT ALL PRIVILEGES ON *.* TO 'dev'@'%'"
  mysql -prootpw -e "FLUSH PRIVILEGES"
  restart_services mysql
}

IP_ADDRESS=$(ifconfig ens3 | grep "inet " | awk -F'[: ]+' '{ print $4 }')

declare -A SERVICES_MAP=(
    ["postgresql"]="5432"
    ["elasticsearch"]="9200"
    ["prometheus"]="9090"
    ["consul-dev"]="8500"
    ["vault-dev"]="8200"
    ["varnish"]="80"
    ["apache2"]="8080"
    ["mysql"]="3306"
)

install_packages apt-transport-https default-jre unzip
add_elasticsearch_repo

for service in vault mysql ; do
  generate_certificates "$service"
done

add_debconf_selection "mysql-server mysql-server/root_password password rootpw"
add_debconf_selection "mysql-server mysql-server/root_password_again password rootpw"

install_packages postgresql elasticsearch apache2 varnish mysql-server mysql-client
stop_services apache2 varnish
setup_mysql
setup_prometheus
setup_consul
setup_vault
setup_apache
setup_varnish
expose_ports
check_services
show_services_table
