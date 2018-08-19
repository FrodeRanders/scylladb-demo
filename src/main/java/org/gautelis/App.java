package org.gautelis;

import com.datastax.driver.core.BoundStatement;
import com.datastax.driver.core.Cluster;
import com.datastax.driver.core.PreparedStatement;
import com.datastax.driver.core.Session;

import java.net.InetSocketAddress;

import static java.util.UUID.randomUUID;


public class App {
    public static void main(String[] args) {
        try (Cluster cluster = Cluster.builder()
                .addContactPointsWithPorts(
                        new InetSocketAddress("localhost", 9042),
                        new InetSocketAddress("localhost", 9043),
                        new InetSocketAddress("localhost", 9044))
                .withCredentials("cassandra", "cassandra")
                .build()) {

            try (Session session = cluster.connect("test")) {

                PreparedStatement myPreparedInsert = session.prepare(
                        "INSERT INTO ttt(id, code) VALUES (?,?)"
                );

                //BoundStatement myInsert = myPreparedInsert
                //        .bind(randomUUID(), 42);

                BoundStatement myInsert = myPreparedInsert
                        .bind(2, 42);

                session.execute(myInsert);
            }
        }
    }
}
