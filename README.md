# Demonstrating a setup of ScyllaDB (in Docker) and a short demo program

## Retrieve latest version of ScyllaDB from the Docker registry

```bash
docker pull scylladb/scylla
```

## Prepare for setting up ScyllaDB in a local development cluster

We want the Scylla containers to store it's database files outside of the ephemeral container. In order to achieve this, we will provide a local directory (in my case ```~/scylla/mapped```) to all Scylla containers, which is mounted as a volume in the container (cf. the following figure).

![Image](https://docs.docker.com/storage/images/types-of-mounts-bind.png?raw=true)

By keeping the database files outside of the Scylla containers, the data will survive the lifetime(s) of the individual Scylla containers.

The last piece of information we need is that each ScyllaDB instance is configured by means of the file ```/etc/scylla/scylla.yaml``` within each respective container. We want to provide a uniqe configuration file to each ScyllaDB instance and the easiest way to do this is to externalize this file from each container. 

The default ScyllaDB configuration file is present as ```/etc/scylla/scylla.yaml``` in the ```scylladb/scylla``` image but we will overlay it with our own configuration file -- one unique file per ScyllaDB instance (i.e. one unique file per ScyllaDB container).

Using raw Docker, we will have to be explicit about network ports, but more on that later on.

## Prepare configuration

First we need to determine a suitable configuration file template for our setup. We want to do this since we need to modify the configuration of at least one ScyllaDB instance (in order to authenticate for keyspace creation) and possibly for all ScyllaDB instances.

You could start by retrieving a template from [GitHub](https://github.com/scylladb/scylla/blob/master/conf/scylla.yaml), but it may differ from the one bundled with the ScyllaDB image (which in fact it does!) The best is to pick the one bundled with the image as a template.

If you want to pull a template from GitHub, do something like this:

```bash
➜ curl https://raw.githubusercontent.com/scylladb/scylla/master/conf/scylla.yaml -o scylla-template.yaml
```

If you instead want to pull a template from the container (recommended!), do something like this:

```bash
➜ docker run scylladb/scylla just-some-unrecognised-argument
➜ docker export $(docker ps -lq) | tar xf - etc/scylla/scylla.yaml
➜ docker rm $(docker ps -lq)
➜ cp ./etc/scylla/scylla.yaml ./scylla-template.yaml
```

Next we need to add some lines to the template in order to allow us to connect as an authenticated user and create keyspaces and such:

```bash
➜ cat >> ./scylla-template.yaml <<EOF

authenticator: 'com.scylladb.auth.TransitionalAuthenticator'
authorizer: 'com.scylladb.auth.TransitionalAuthorizer'
EOF
```

There are some network ports that are configurable as well:

* A native transport port (without SSL): 9042 (default)
* A native transport port (with SSL): 9142
* An RPC listener port (Thrift): 9160
* A REST API service port: 10000

The default super user is ```cassandra``` with password ```cassandra```.

## Start a three-node ScyllaDB cluster on the local machine for testing purposes

### Node 1

Clone the scylla-template.yaml for node 1.

```bash
➜ cp scylla-template.yaml scylla-node1.yaml
```

We want to run the first ScyllaDB instance in a container, exposing the internal native transport port ```9042``` available as ```9042``` on the host.
I am mounting a local directory (```~/scylla/mapped/node1```) as a volume in the container, and also bind-mounting (overlaying) the external configuration file on top of the existing configuration file.

Currently, for the sake of this demo, I am only exposing the native transport port (```9042```) but the rest can be exposed as well.

```bash
➜ docker run --name scylla-node1 --publish 9042:9042 \
             --volume /Users/froran/scylla/mapped/node1:/var/lib/scylla \
             --volume /Users/froran/scylla/scylla-node1.yaml:/etc/scylla/scylla.yaml \
             --detach scylladb/scylla
```

In order to actually create a cluster of such nodes, subsequent nodes need to find this node (any node actually). The following command can be used to determine the IP-address of ```scylla-node1``` in the docker environment.

```bash
➜ docker inspect --format='{{ .NetworkSettings.IPAddress }}' scylla-node1
172.17.0.2
```

### Node 2

Clone the scylla-template.yaml for node 2.

```bash
➜ cp scylla-template.yaml scylla-node2.yaml
```

We want to run the next (and second) ScyllaDB instance in a container, exposing the internal native transport port ```9042``` available as ```9043``` on the host.
I am mounting a local directory (```~/scylla/mapped/node2```) as a volume in the container, and also bind-mounting (overlaying) the external configuration file on top of the existing configuration file.

```bash
➜ docker run --name scylla-node2 --publish 9043:9042 \
             --volume /Users/froran/scylla/mapped/node2:/var/lib/scylla \
             --volume /Users/froran/scylla/scylla-node2.yaml:/etc/scylla/scylla.yaml \
             --detach scylladb/scylla \
             --seeds="$(docker inspect --format='{{ .NetworkSettings.IPAddress }}' scylla-node1)"
```

### Node 3

Clone the scylla-template.yaml for node 3.

```bash
➜ cp scylla-template.yaml scylla-node3.yaml
```

We want to run the next (and third) ScyllaDB instance in a container, exposing the internal native transport port ```9042``` available as ```9044``` on the host.
I am mounting a local directory (```~/scylla/mapped/node3```) as a volume in the container, and also bind-mounting (overlaying) the external configuration file on top of the existing configuration file.

```bash
➜ docker run --name scylla-node3 --publish 9044:9042 \
             --volume /Users/froran/scylla/mapped/node3:/var/lib/scylla \
             --volume /Users/froran/scylla/scylla-node3.yaml:/etc/scylla/scylla.yaml \
             --detach scylladb/scylla \
             --seeds="$(docker inspect --format='{{ .NetworkSettings.IPAddress }}' scylla-node1)"
```

## Checking the cluster status

The cluster status can be queried by executing the ```nodetool``` in a running container, say in ```scylla-node1``` (the first instance of ScyllaDB).

```bash
➜ docker exec -it scylla-node1 nodetool status
Datacenter: datacenter1
=======================
Status=Up/Down
|/ State=Normal/Leaving/Joining/Moving
--  Address     Load       Tokens       Owns    Host ID                               Rack
UN  172.17.0.3  533.16 KB  256          ?       e4a05d0d-8b30-471f-b2e3-626215a62464  rack1
UN  172.17.0.2  603.5 KB   256          ?       4dab9d8d-cbe9-4ef2-8317-d99cd75122af  rack1
UJ  172.17.0.4  ?          256          ?       e51352e7-3b70-4b4d-b52a-a8144bb5d636  rack1
```

So, the ```scylla-node3``` seem to be still joining the cluster -- wait and see :)

```bash
➜ docker exec -it scylla-node1 nodetool status
Datacenter: datacenter1
=======================
Status=Up/Down
|/ State=Normal/Leaving/Joining/Moving
--  Address     Load       Tokens       Owns    Host ID                               Rack
UN  172.17.0.3  587.5 KB   256          ?       e4a05d0d-8b30-471f-b2e3-626215a62464  rack1
UN  172.17.0.2  658.17 KB  256          ?       4dab9d8d-cbe9-4ef2-8317-d99cd75122af  rack1
UN  172.17.0.4  592.63 KB  256          ?       e51352e7-3b70-4b4d-b52a-a8144bb5d636  rack1
```

Now ```scylla-node3``` has successfully joined the cluster with ```scylla-node1``` and ```scylla-node2```.

## Steps for reconfiguring a node in a running cluster

You may edit the configuration file of a cluster node either from the host or from within the container, but in any case you will have to restart the ScyllaDB instance.

For the sake of this demo, we will modify the configuration from within the container (from a Bash shell).

```
➜ docker exec -it scylla-node1 /bin/bash

[root@ae4179b857f0 /]# vi /etc/scylla/scylla.yaml
[root@ae4179b857f0 /]# exit
```

Restart ScyllaDB in node 1.

```bash
➜ docker exec -it scylla-node1 supervisorctl restart scylla
scylla: stopped
scylla: started
```

## Creating a keyspace and a table

We will use ```cqlsh``` (the Cassandra Query Language Shell) to create a keyspace and a table, that we will later modify from our demo program.

```bash
➜ docker exec -it scylla-node1 cqlsh -ucassandra -pcassandra
Connected to  at 172.17.0.2:9042.
[cqlsh 5.0.1 | Cassandra 3.0.8 | CQL spec 3.3.1 | Native protocol v4]
Use HELP for help.
cassandra@cqlsh> LIST users;

 name      | super
-----------+-------
 cassandra |  True

(1 rows)

cassandra@cqlsh> CREATE KEYSPACE demo WITH REPLICATION = { 'class' : 'SimpleStrategy', 'replication_factor' : 2 } AND DURABLE_WRITES=true;

cassandra@cqlsh> DESCRIBE keyspaces;

system_traces  system_schema  system  demo

cassandra@cqlsh> USE demo;

cassandra@cqlsh:demo> CREATE TABLE IF NOT EXISTS contract (id INT PRIMARY KEY, code INT);

cassandra@cqlsh:demo> DESCRIBE contract;

CREATE TABLE demo.contract (
    id int PRIMARY KEY,
    code int
) WITH bloom_filter_fp_chance = 0.01
    AND caching = {'keys': 'ALL', 'rows_per_partition': 'ALL'}
    AND comment = ''
    AND compaction = {'class': 'SizeTieredCompactionStrategy'}
    AND compression = {}
    AND crc_check_chance = 1.0
    AND dclocal_read_repair_chance = 0.1
    AND default_time_to_live = 0
    AND gc_grace_seconds = 864000
    AND max_index_interval = 2048
    AND memtable_flush_period_in_ms = 0
    AND min_index_interval = 128
    AND read_repair_chance = 0.0
    AND speculative_retry = '99.0PERCENTILE';

cassandra@cqlsh:demo> SELECT * FROM contract;

 id | code
----+------

(0 rows)

cassandra@cqlsh:demo> INSERT INTO contract (id,code) VALUES (1, 42);

cassandra@cqlsh:demo> SELECT * FROM contract;

 id | code
----+------
  1 |   42

(1 rows)

cassandra@cqlsh:demo> exit
```

## Connecting from a client

This [simple demo](https://github.com/FrodeRanders/scylladb-demo/blob/master/src/main/java/org/gautelis/scylla/demo/App.java) program describes how to connect to the cluster and issue CQL statements from Java.

The demo program will just add lots of rows to the 'contract' table, almost 100.000 rows.

```
➜ docker exec -it scylla-node1 cqlsh -ucassandra -pcassandra
Connected to  at 172.17.0.2:9042.
[cqlsh 5.0.1 | Cassandra 3.0.8 | CQL spec 3.3.1 | Native protocol v4]
Use HELP for help.
cassandra@cqlsh> SELECT COUNT(*) FROM demo.contract;

 count
-------
 99999

(1 rows)
cassandra@cqlsh> exit
```

## Stopping the cluster

First, we need to bring down the cluster nodes in an orderly fashion.

```bash
➜ docker exec -it scylla-node3 supervisorctl stop scylla
➜ docker exec -it scylla-node2 supervisorctl stop scylla
➜ docker exec -it scylla-node1 supervisorctl stop scylla
```

Next, the containers can be stopped and removed.

```bash
➜ scylla docker ps --all
CONTAINER ID        IMAGE               COMMAND                  CREATED             STATUS              PORTS                                                                  NAMES
e11d225bb296        scylladb/scylla     "/docker-entrypoint.…"   15 minutes ago      Up 15 minutes       7000-7001/tcp, 9160/tcp, 9180/tcp, 10000/tcp, 0.0.0.0:9044->9042/tcp   scylla-node3
e79f3d62d489        scylladb/scylla     "/docker-entrypoint.…"   17 minutes ago      Up 17 minutes       7000-7001/tcp, 9160/tcp, 9180/tcp, 10000/tcp, 0.0.0.0:9043->9042/tcp   scylla-node2
ae4179b857f0        scylladb/scylla     "/docker-entrypoint.…"   About an hour ago   Up About an hour    7000-7001/tcp, 9160/tcp, 9180/tcp, 10000/tcp, 0.0.0.0:9042->9042/tcp   scylla-node1

➜ docker stop e11d225bb296 e79f3d62d489 ae4179b857f0
➜ docker rm e11d225bb296 e79f3d62d489 ae4179b857f0
```
