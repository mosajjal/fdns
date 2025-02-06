#!/bin/bash
set -e

echo "welcome to the installation wizard for fdns"
echo "make sure you have docker compose (the new version) installed"
echo "this script also uses the following commands, make sure all of them are available"
echo "openssl, sed, curl, jq"

read -p "What is the DNS retention policy (days) on this host? default is 30: " ttl_days
ttl_days=${ttl_days:-30}
new_ttl_line="$ttl_days DAY DELETE -- DNS_TTL_VARIABLE"
old_ttl_line="7 DAY DELETE -- DNS_TTL_VARIABLE"

sed -i "s/$old_ttl_line/$new_ttl_line/" ./clickhouse/tables.sql

echo "this builder expects you to maintain a certificate and key in the current directory under the filenames"
read -p "cert.pem and key.pem. For testing, I can create a self-signed certificate for you. would you like to do that? " selfsign
if [ "$selfsign" == "y" ] || [ "$selfsign" == "Y" ]; then
    read -p "enter your hostname: " hostname
    openssl req -subj "/CN=$hostname" -addext "subjectAltName=DNS:$hostname,DNS:*.$hostname" -x509 -sha256 -newkey rsa:2048 -keyout key.pem -out cert.pem -days 365 -nodes
    # fix permissions
    chmod 755 key.pem
fi

echo "Starting the containers..."
docker compose up --detach

echo "Adding the datasources to Grafana"
curl -H 'Content-Type:application/json' 'http://admin:admin@127.0.0.1:3000/api/datasources' --data-raw '{"name":"ClickHouse","type":"vertamedia-clickhouse-datasource","url":"http://clickhouse:8123","access":"proxy"}'
curl -H 'Content-Type:application/json' 'http://admin:admin@127.0.0.1:3000/api/datasources' --data-raw '{"name":"VictoriaMetrics", "type":"prometheus","access":"proxy","url":"http://victoriametrics:8428"}'
echo
echo "Adding the dashboards to Grafana"
dashboard_json=`cat grafana/dnsmonitoring.json | bin/jq '{Dashboard:.} | .Dashboard.id = null'`
curl -H 'Content-Type:application/json' 'http://admin:admin@127.0.0.1:3000/api/dashboards/db' --data "$dashboard_json"
metrics_json=`cat grafana/metrics.json | bin/jq '{Dashboard:.} | .Dashboard.id = null'`
curl -H 'Content-Type:application/json' 'http://admin:admin@127.0.0.1:3000/api/dashboards/db' --data "$metrics_json"
echo

echo "restarting grafana container after plugin installation"
sleep 5
docker compose restart grafana

# echo
echo "Completed! You can visit http://$hostname:3000 using admin/admin as credentials to see your dashboard."


echo "IMPORTANT: your build still relies on some files in this directory, please don't move or delete this folder"
