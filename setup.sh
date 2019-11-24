#!/bin/bash

LOCATION="${HOME}/scylla"
IMAGE=scylladb/scylla
PORT=9042

recreate_persistent_store() {
    for d in ${LOCATION}/mapped/node{1,2,3}; do
        echo "Re-creating $d"
        rm -rf $d
        mkdir $d
    done
}

stop_and_remove_container() {
    echo "Stopping and removing container $1"
    docker stop $1
    docker rm $1
}

stop_and_remove_all_containers() {
    for c in $(docker ps --all | awk '{print $1;}'); do
        if [ "$c" != "CONTAINER" ]; then
	    stop_and_remove_container $c
        fi
    done
}

run_scylla() {
    docker run --name "scylla-node$1" --publish $2:${PORT} \
               --volume ${LOCATION}/mapped/node$1:/var/lib/scylla \
               --volume ${LOCATION}/scylla.yaml:/etc/scylla/scylla.yaml \
               --detach ${IMAGE}
}

append_scylla() {
    docker run --name "scylla-node$1" --publish $2:${PORT} \
               --volume ${LOCATION}/mapped/node$1:/var/lib/scylla \
               --volume ${LOCATION}/scylla.yaml:/etc/scylla/scylla.yaml \
               --detach ${IMAGE} \
               --seeds="$(docker inspect --format='{{ .NetworkSettings.IPAddress }}' scylla-node1)"
}



# Prepare
if [ ! -d ${LOCATION} ]; then
    echo "First time preparations"
    mkdir ${LOCATION}
    docker pull scylladb/scylla
    docker run scylladb/scylla just-some-unrecognised-argument > /dev/null 2>&1 
    docker cp $(docker ps -lq):/etc/scylla/scylla.yaml ${LOCATION}/scylla.yaml
    docker rm $(docker ps -lq)
    cat >> ${LOCATION}/scylla.yaml <<EOF

authenticator: 'com.scylladb.auth.TransitionalAuthenticator'
authorizer: 'com.scylladb.auth.TransitionalAuthorizer'

#

EOF
    
fi

# May be a bit drastic in general, but uncomment if you want to always start from known ground
#stop_and_remove_all_containers

#
run_scylla 1 9042 

# Await the first node coming up
TIME=60
echo "Waiting for the first node to come up (${TIME} sec)"
sleep ${TIME}

docker exec -i scylla-node1 cqlsh -ucassandra -pcassandra <<EOF
CREATE KEYSPACE demo WITH REPLICATION = { 'class' : 'SimpleStrategy', 'replication_factor' : 2 } AND DURABLE_WRITES=true;
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
exit;
EOF

docker exec -i scylla-node1 nodetool status demo 

#
append_scylla 2 9043 
append_scylla 3 9044 

# Give the next to nodes some leeway 
TIME=60
echo "Wait for the next two nodes to come up (${TIME} sec)"
sleep ${TIME}

docker exec -i scylla-node1 nodetool status demo 

echo done
