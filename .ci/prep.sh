#!/bin/bash

set -euo pipefail

set -x
export MYSQL_VERSION="${MYSQL_VERSION:-8.4}"
export MYSQL_CERTS_DIR='/etc/mysql_certs'

mkdir -p .ci/run .ci/certs
SSLDIR=/etc/mysql_certs make tests-prep
mv test/ssl/my-ssl.cnf .ci/
# Need to run with sudo here because later the files are changed to be owned by mysql user in docker container
# If the script is re-run (probably not in CI, but when running locally), cp without sudo will fail.
sudo cp test/ssl/ca.pem .ci/certs/
sudo mv test/ssl/server-key.pem .ci/certs/
sudo mv test/ssl/server-cert.pem .ci/certs/
sudo chmod 660 .ci/certs/*

if [ ${MYSQL_VERSION} = '8.4' ]; then
    echo 'mysql_native_password=on' >> .ci/my-ssl.cnf
fi

# the host has no mysql user, issue a docker run command to change owner
docker run --rm -t -v $(pwd)/.ci/certs:${MYSQL_CERTS_DIR} mysql:${MYSQL_VERSION} chown -R mysql:mysql ${MYSQL_CERTS_DIR}
# now start mysql with config files and certificate files mouted as volumes
docker compose -f .ci/docker-compose.yml up -d --wait

# wait for mysqld to be ready
is_mysqld_ready() {
    docker logs mysql 2>&1 | grep -qE 'socket:\s.+var/run/.+port:\s3306'
}

MAX_ATTEMPTS=6
attempt=0
while ! is_mysqld_ready; do
    attempt=$((attempt + 1))
    if [ "$attempt" -ge "$MAX_ATTEMPTS" ]; then
        echo "Failed to connect to MySQL server after $MAX_ATTEMPTS attempts."
        exit 1
    fi
    sleep 5
done

# finally initialize test users
docker exec mysql /init.sh
