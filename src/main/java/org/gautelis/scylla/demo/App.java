package org.gautelis.scylla.demo;

import com.datastax.driver.core.BoundStatement;
import com.datastax.driver.core.Cluster;
import com.datastax.driver.core.PreparedStatement;
import com.datastax.driver.core.Session;

import java.net.InetSocketAddress;


public class App {
    public static void main(String[] args) {
        try (Cluster cluster = Cluster.builder()
                .addContactPointsWithPorts(
                        new InetSocketAddress("localhost", 9042),
                        new InetSocketAddress("localhost", 9043),
                        new InetSocketAddress("localhost", 9044))
                .withCredentials("cassandra", "cassandra")
                .build()) {

            try (Session session = cluster.connect("demo")) {

                PreparedStatement myPreparedInsert = session.prepare(
                        "INSERT INTO contract(id, code) VALUES (?,?)"
                );

                for (int i = 2; i < 100000; i++) {
                   BoundStatement myInsert = myPreparedInsert.bind(i, 42 + i);
                   session.execute(myInsert);
                }
            }
        }
    }
}
