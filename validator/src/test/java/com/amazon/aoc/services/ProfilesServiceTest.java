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

import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTimeoutPreemptively;

import com.amazonaws.auth.AWSStaticCredentialsProvider;
import com.amazonaws.auth.BasicAWSCredentials;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketTimeoutException;
import java.time.Duration;
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
              500);
      assertTimeoutPreemptively(
          Duration.ofSeconds(10),
          () -> assertThrows(SocketTimeoutException.class, () -> service.profileTypes(0, 1)));
    }
  }
}
