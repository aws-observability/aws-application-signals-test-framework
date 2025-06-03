/*
 * Copyright Amazon.com, Inc. or its affiliates.
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

package com.amazon.sampleapp;

import io.opentelemetry.api.trace.Span;
import java.net.URI;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.sql.Connection;
import java.util.concurrent.Executors;
import java.util.concurrent.ScheduledExecutorService;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicBoolean;
import org.apache.http.HttpEntity;
import org.apache.http.client.methods.CloseableHttpResponse;
import org.apache.http.client.methods.HttpGet;
import org.apache.http.impl.client.CloseableHttpClient;
import org.apache.http.impl.client.HttpClients;
import org.apache.http.util.EntityUtils;
import org.apache.tomcat.util.codec.binary.Base64;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Bean;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetBucketLocationRequest;

@Controller
public class FrontendServiceController {
  private static final Logger logger = LoggerFactory.getLogger(FrontendServiceController.class);
  private final CloseableHttpClient httpClient;
  private final S3Client s3;
  private AtomicBoolean shouldSendLocalRootClientCall = new AtomicBoolean(false);

  @Bean
  private void runLocalRootClientCallRecurringService() { // run the service
    ScheduledExecutorService executorService = Executors.newSingleThreadScheduledExecutor();

    Runnable runnableTask =
            () -> {
              if (shouldSendLocalRootClientCall.get()) {
                shouldSendLocalRootClientCall.set(false);
                HttpGet request = new HttpGet("http://local-root-client-call");
                try (CloseableHttpResponse response = httpClient.execute(request)) {
                  HttpEntity entity = response.getEntity();
                  if (entity != null) {
                    logger.info(EntityUtils.toString(entity));
                  }
                } catch (Exception e) {
                  logger.error("Error in recurring task: {}", e.getMessage());
                }
              }
            };
    // Run with initial 0.1s delay, every 1 second
    executorService.scheduleAtFixedRate(runnableTask, 100, 1000, TimeUnit.MILLISECONDS);
  }

  @Autowired
  public FrontendServiceController(CloseableHttpClient httpClient, S3Client s3) {
    this.httpClient = httpClient;
    this.s3 = s3;
  }

  @GetMapping("/")
  @ResponseBody
  public String healthcheck() {
    return "healthcheck";
  }

  // test aws calls instrumentation
  @GetMapping("/aws-sdk-call")
  @ResponseBody
  public String awssdkCall(@RequestParam(name = "testingId", required = false) String testingId) {
    String bucketName = "e2e-test-bucket-name";
    if (testingId != null) {
      bucketName += "-" + testingId;
    }
    logger.warn("This is a custom log for validation testing");
    GetBucketLocationRequest bucketLocationRequest =
            GetBucketLocationRequest.builder().bucket(bucketName).build();
    try {
      s3.getBucketLocation(bucketLocationRequest);
    } catch (Exception e) {
      logger.error("Error occurred when trying to get bucket location of: " + bucketName, e);
    }
    return getXrayTraceId();
  }

  // test http instrumentation (Apache HttpClient for Java 8)
  @GetMapping("/outgoing-http-call")
  @ResponseBody
  public String httpCall() {
    HttpGet request = new HttpGet("https://www.amazon.com");
    try (CloseableHttpResponse response = httpClient.execute(request)) {
      int statusCode = response.getStatusLine().getStatusCode();
      logger.info("outgoing-http-call status code: " + statusCode);
    } catch (Exception e) {
      logger.error("Could not complete HTTP request: {}", e.getMessage());
    }
    return getXrayTraceId();
  }

  // RemoteService must also be deployed to use this API
  @GetMapping("/remote-service")
  @ResponseBody
  public String downstreamService(@RequestParam("ip") String ip) {
    ip = ip.replace("/", "");
    HttpGet request = new HttpGet("http://" + ip + ":8080/healthcheck");
    try (CloseableHttpResponse response = httpClient.execute(request)) {
      int statusCode = response.getStatusLine().getStatusCode();
      logger.info("Remote service call status code: " + statusCode);
      return getXrayTraceId();
    } catch (Exception e) {
      logger.error("Could not complete HTTP request to remote service: {}", e.getMessage());
    }
    return getXrayTraceId();
  }

  // Test Local Root Client Span generation
  @GetMapping("/client-call")
  @ResponseBody
  public String asyncService() {
    logger.info("Client-call received");
    shouldSendLocalRootClientCall.set(true);
    return "{\"traceId\": \"1-00000000-000000000000000000000000\"}";
  }

  // Uses the /mysql endpoint to make an SQL call
  @GetMapping("/mysql")
  @ResponseBody
  public String mysql() {
    logger.info("mysql received");
    final String rdsMySQLClusterPassword = new String(new Base64().decode(System.getenv("RDS_MYSQL_CLUSTER_PASSWORD").getBytes()));
    try {
      Connection connection = DriverManager.getConnection(
              System.getenv("RDS_MYSQL_CLUSTER_CONNECTION_URL"),
              System.getenv("RDS_MYSQL_CLUSTER_USERNAME"),
              rdsMySQLClusterPassword);
      Statement statement = connection.createStatement();
      statement.executeQuery("SELECT * FROM tables LIMIT 1;");
    } catch (SQLException e) {
      logger.error("Could not complete SQL request: {}", e.getMessage());
      throw new RuntimeException(e);
    }
    return getXrayTraceId();
  }

  // get x-ray trace id
  private String getXrayTraceId() {
    String traceId = Span.current().getSpanContext().getTraceId();
    String xrayTraceId = "1-" + traceId.substring(0, 8) + "-" + traceId.substring(8);
    return String.format("{\"traceId\": \"%s\"}", xrayTraceId);
  }
}
