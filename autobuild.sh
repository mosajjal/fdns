#!/bin/bash
set -e

read -p "What is the DNS retention policy (days) on this host? default is 30: " ttl_days
ttl_days=${ttl_days:-30}
new_ttl_line="TTL DnsDate + INTERVAL $ttl_days DAY -- DNS_TTL_VARIABLE"
old_ttl_line="TTL DnsDate + INTERVAL 30 DAY -- DNS_TTL_VARIABLE"

sed -i "s/$old_ttl_line/$new_ttl_line/" ./clickhouse/tables.sql

echo "Starting the containers..."
docker compose up -d

echo "Waiting 20 seconds for Containers to be fully up and running "
sleep 5

echo "Create tables for Clickhouse"
docker compose exec clickhouse /bin/sh -c 'cat /tmp/tables.sql | clickhouse-client -h 127.0.0.1 --multiquery'

echo "downloading latest version of Clickhouse plugin for Grafana"
docker compose exec grafana grafana-cli plugins install vertamedia-clickhouse-datasource

echo "restarting grafana container after plugin installation"
docker compose restart grafana
sleep 1

echo "Adding the datasource to Grafana"
docker compose exec grafana /sbin/curl -H 'Content-Type:application/json' 'http://admin:admin@127.0.0.1:3000/api/datasources' --data-raw '{"name":"ClickHouse","type":"vertamedia-clickhouse-datasource","url":"http://clickhouse:8123","access":"proxy"}'
echo

echo "Adding the dashboard to Grafana"
dashboard_json=`cat grafana/panel.json | bin/jq '{Dashboard:.} | .Dashboard.id = null'`
docker compose exec grafana /sbin/curl -H 'Content-Type:application/json' 'http://admin:admin@127.0.0.1:3000/api/dashboards/db' --data "$dashboard_json"
echo

# echo
echo "Completed! You can visit http://$hostname:3000 using admin/admin as credentials to see your dashboard."


echo "IMPORTANT: your build still relies on some files in this directory, please don't move or delete this folder"
