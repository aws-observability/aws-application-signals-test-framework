/*
 * Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").
 * You may not use this file except in compliance with the License.
 * A copy of the License is located at
 *
 *  http://aws.amazon.com/apache2.0
 *
 * or in the "license" file accompanying this file. This file is distributed
 * on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
 * express or implied. See the License for the specific language governing
 * permissions and limitations under the License.
 */

package com.amazon.aoc.services;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTimeoutPreemptively;

import com.amazonaws.auth.AWSStaticCredentialsProvider;
import com.amazonaws.auth.BasicAWSCredentials;
import com.sun.net.httpserver.HttpServer;
import java.net.InetSocketAddress;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketTimeoutException;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;

public class ProfilesServiceTest {

  /** A query to a server that accepts the connection but never answers fails instead of hanging. */
  @Test
  public void testStalledQueryTimesOut() throws Exception {
    try (ServerSocket server = new ServerSocket(0)) {
      Thread acceptor =
          new Thread(
              () -> {
                try (Socket ignored = server.accept()) {
                  Thread.sleep(Long.MAX_VALUE);
                } catch (Exception e) {
                  // Closed when the test ends.
                }
              });
      acceptor.setDaemon(true);
      acceptor.start();

      ProfilesService service =
          new ProfilesService(
              "http://127.0.0.1:" + server.getLocalPort(),
              "us-east-1",
              new AWSStaticCredentialsProvider(new BasicAWSCredentials("key", "secret")),
              500,
              1L);
      assertTimeoutPreemptively(
          Duration.ofSeconds(10),
          () -> assertThrows(SocketTimeoutException.class, () -> service.profileTypes(0, 1)));
    }
  }

  /** A server answering HTTP 429 to the first {@code throttled} requests, then {} with 200. */
  private static HttpServer throttlingServer(int throttled, AtomicInteger requests)
      throws Exception {
    HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
    server.createContext(
        "/",
        exchange -> {
          int n = requests.incrementAndGet();
          byte[] body =
              (n <= throttled ? "{\"code\":\"resource_exhausted\"}" : "{\"profileTypes\":[]}")
                  .getBytes(StandardCharsets.UTF_8);
          exchange.sendResponseHeaders(n <= throttled ? 429 : 200, body.length);
          exchange.getResponseBody().write(body);
          exchange.close();
        });
    server.start();
    return server;
  }

  private static ProfilesService serviceFor(HttpServer server) {
    return new ProfilesService(
        "http://127.0.0.1:" + server.getAddress().getPort(),
        "us-east-1",
        new AWSStaticCredentialsProvider(new BasicAWSCredentials("key", "secret")),
        5_000,
        1L);
  }

  /** A throttled query is retried on its own and succeeds once the API stops throttling. */
  @Test
  public void testThrottledQueryIsRetried() throws Exception {
    AtomicInteger requests = new AtomicInteger();
    HttpServer server = throttlingServer(2, requests);
    try {
      serviceFor(server).profileTypes(0, 1);
      assertEquals(3, requests.get());
    } finally {
      server.stop(0);
    }
  }

  /** Throttling that does not stop fails the query after a bounded number of attempts. */
  @Test
  public void testPersistentThrottlingFails() throws Exception {
    AtomicInteger requests = new AtomicInteger();
    HttpServer server = throttlingServer(Integer.MAX_VALUE, requests);
    try {
      RuntimeException e =
          assertThrows(RuntimeException.class, () -> serviceFor(server).profileTypes(0, 1));
      org.junit.jupiter.api.Assertions.assertTrue(e.getMessage().contains("HTTP 429"));
      assertEquals(6, requests.get());
    } finally {
      server.stop(0);
    }
  }
}
