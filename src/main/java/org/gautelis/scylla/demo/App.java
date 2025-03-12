package org.gautelis.scylla.demo;

import com.datastax.oss.driver.api.core.CqlSession;
import com.datastax.oss.driver.api.core.cql.BoundStatement;
import com.datastax.oss.driver.api.core.cql.PreparedStatement;
import java.net.InetSocketAddress;


public class App {
    public static void main(String[] args) {
        // Build a session:
        // - Provide contact points (each with host + port).
        // - Provide local datacenter name, which must match your cluster config (e.g. "dc1" or "datacenter1").
        // - Provide credentials if you have a PasswordAuthenticator/TransitionalAuthenticator.
        // - Optional: specify the keyspace here with .withKeyspace("demo").
        try (CqlSession session = CqlSession.builder()
                .addContactPoint(new InetSocketAddress("localhost", 9042))
                .addContactPoint(new InetSocketAddress("localhost", 9043))
                .addContactPoint(new InetSocketAddress("localhost", 9044))
                .withLocalDatacenter("datacenter1")
                .withAuthCredentials("cassandra", "cassandra")
                .withKeyspace("demo")
                .build()) {

            // Prepare a statement (using "contract" table in keyspace "demo").
            // If you didn't set .withKeyspace("demo"), then you'd do:
            // session.prepare("INSERT INTO demo.contract(id, code) VALUES (?, ?)");
            PreparedStatement statement = session.prepare(
                    "INSERT INTO contract (id, code) VALUES (?, ?)"
            );

            // Execute multiple inserts in a loop
            for (int i = 2; i < 100000; i++) {
                BoundStatement bound = statement.bind(i, 42 + i);
                session.execute(bound);
            }
        }
    }
}
