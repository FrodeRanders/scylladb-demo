#!/bin/bash
set -euo pipefail

LOCATION="$(pwd)/transient"
IMAGE=scylladb/scylla
PORT=9042
NETWORK_NAME="scylla-cluster"
MIN_AIO=1081626

recreate_persistent_store() {
    for d in ${LOCATION}/mapped/node{1,2,3}; do
        echo "Re-creating $d"
        rm -rf "$d"
        mkdir -p "$d"
    done
}

stop_and_remove_container() {
    echo "Stopping and removing container $1"
    docker stop "$1" || true
    docker rm "$1" || true
}

stop_and_remove_all_containers() {
    for c in $(docker ps --all --format '{{.Names}}'); do
        stop_and_remove_container "$c"
    done
}

create_network_if_missing() {
    if ! docker network ls --format '{{.Name}}' | grep -q "^${NETWORK_NAME}\$"; then
        echo "Creating network: ${NETWORK_NAME}"
        docker network create "${NETWORK_NAME}"
    else
        echo "Network ${NETWORK_NAME} already exists."
    fi
}

run_once() {
    echo "Temporarily change fs.aio-max-nr in Docker Desktop’s internal VM"

    docker run --rm -it \
      --privileged \
      --pid=host \
      --net=host \
      alpine:latest \
      nsenter -t 1 -m -u -n -i \
      sysctl -w fs.aio-max-nr=${MIN_AIO}
}

# We are running with restrictions
# --smp 1 sets the number of CPU threads within the container for Scylla (useful if you’re just testing).
# --memory 1G sets the memory limit that Scylla will use.
# --overprovisioned 1 allows Scylla to run in a more “forgiving” environment (think development scenarios).
run_scylla() {
    # run_scylla <node_number> <host_port>
    NODE_NUM=$1
    HOST_PORT=$2
    CONTAINER_NAME="scylla-node${NODE_NUM}"
    echo "Starting seed node: ${CONTAINER_NAME}"

    docker run --name "${CONTAINER_NAME}" \
               --hostname "${CONTAINER_NAME}" \
               --network "${NETWORK_NAME}" \
               --publish "${HOST_PORT}:${PORT}" \
               --volume "${LOCATION}/mapped/node${NODE_NUM}:/var/lib/scylla" \
               --volume "${LOCATION}/scylla.yaml:/etc/scylla/scylla.yaml" \
               --detach "${IMAGE}" \
               --smp 1 --memory 1G --overprovisioned 1 \
               --seeds="scylla-node1"
}

# We are running with restrictions
# --smp 1 sets the number of CPU threads within the container for Scylla (useful if you’re just testing).
# --memory 1G sets the memory limit that Scylla will use.
# --overprovisioned 1 allows Scylla to run in a more “forgiving” environment (think development scenarios).
append_scylla() {
    # append_scylla <node_number> <host_port>
    NODE_NUM=$1
    HOST_PORT=$2
    CONTAINER_NAME="scylla-node${NODE_NUM}"
    echo "Starting additional node: ${CONTAINER_NAME}"

    docker run --name "${CONTAINER_NAME}" \
               --hostname "${CONTAINER_NAME}" \
               --network "${NETWORK_NAME}" \
               --publish "${HOST_PORT}:${PORT}" \
               --volume "${LOCATION}/mapped/node${NODE_NUM}:/var/lib/scylla" \
               --volume "${LOCATION}/scylla.yaml:/etc/scylla/scylla.yaml" \
               --detach "${IMAGE}" \
               --smp 1 --memory 1G --overprovisioned 1 \
               --seeds="scylla-node1"
}

#
# MAIN SCRIPT
#

# Start from a clean state
#stop_and_remove_all_containers
#recreate_persistent_store

# If first time, do initial one-time setup:
if [ ! -d "${LOCATION}" ]; then
    echo "First time preparations..."
    mkdir -p "${LOCATION}"
    docker pull "${IMAGE}"

    # Grab a default scylla.yaml from container (without starting it)
    CONTAINER_ID=$(docker create scylladb/scylla)
    docker cp "$CONTAINER_ID:/etc/scylla/scylla.yaml" "${LOCATION}/scylla.yaml"
    docker rm "$CONTAINER_ID"

    cat >> "${LOCATION}/scylla.yaml" <<EOF

# The transitional authenticator basically lets both unauthenticated and authenticated connections proceed,
# so it’s often used for rolling out authentication in an existing cluster or for quick dev setups.
# This means you can still log in as the default user (“cassandra” / “cassandra”) while also allowing
# you to create new users and gradually adopt password-based logins.
authenticator: 'com.scylladb.auth.TransitionalAuthenticator'
authorizer: 'com.scylladb.auth.TransitionalAuthorizer'
EOF
fi

run_once

# Create the Docker network (if not existing)
create_network_if_missing

# Start the first (seed) node on port 9042
run_scylla 1 9042

echo "Waiting 60 seconds for the first node to come up..."
sleep 60

# Create a keyspace & table in the first node
docker exec -i scylla-node1 cqlsh -u cassandra -p cassandra <<EOF
CREATE KEYSPACE demo WITH REPLICATION = { 'class' : 'SimpleStrategy', 'replication_factor' : 3 } AND DURABLE_WRITES=true;
USE demo;
CREATE TABLE IF NOT EXISTS history (
    occasion    TIMESTAMP,
    action      INT, -- 0=init, 1=upgrade
    description VARCHAR,
    major       INT, -- major version
    minor       INT, -- minor version
    PRIMARY KEY (occasion)
);
INSERT INTO history (
    occasion,
    action,
    description,
    major,
    minor
) VALUES (
    toTimeStamp(now()),
    0, -- 'init'
    'Initiating database with schema version 1.0', -- description
    1, -- major version
    0  -- minor version
);
SELECT * FROM history;

CREATE TABLE IF NOT EXISTS contract (id INT PRIMARY KEY, code INT);
exit;
EOF

# Check status on the seed node
docker exec -i scylla-node1 nodetool status demo

# Add second and third nodes (attach them to the same cluster)
append_scylla 2 9043
append_scylla 3 9044

echo "Waiting 60 seconds for the next two nodes to join..."
sleep 60

# Final cluster status
docker exec -i scylla-node1 nodetool status demo

echo "All done! A 3-node Scylla cluster lives on network '${NETWORK_NAME}'."

