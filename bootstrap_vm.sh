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
    apt-get install -y "$@"
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
    download_zip_and_extract "https://releases.hashicorp.com/vault/0.9.3/vault_0.9.3_linux_amd64.zip?_ga=2.54139176.107181496.1517420140-437309316.1517318914" vault
    create_systemd_unit vault-dev root "/usr/local/bin/vault server -dev -dev-listen-address=0.0.0.0:8200"

    enable_services vault-dev
    start_services vault-dev
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

IP_ADDRESS=$(ifconfig ens3 | grep "inet " | awk -F'[: ]+' '{ print $4 }')

install_packages apt-transport-https default-jre
add_elasticsearch_repo
install_packages postgresql elasticsearch apache2 varnish
stop_services apache2 varnish
setup_prometheus
setup_consul
setup_vault
setup_apache
setup_varnish