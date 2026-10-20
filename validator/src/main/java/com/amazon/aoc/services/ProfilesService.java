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

import com.amazonaws.auth.AWS4Signer;
import com.amazonaws.auth.AWSCredentialsProvider;
import com.amazonaws.auth.DefaultAWSCredentialsProviderChain;
import com.amazonaws.auth.STSAssumeRoleSessionCredentialsProvider;
import com.amazonaws.http.AWSRequestSigningApacheInterceptor;
import com.amazonaws.services.securitytoken.AWSSecurityTokenServiceClientBuilder;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ObjectNode;
import java.nio.charset.StandardCharsets;
import lombok.extern.log4j.Log4j2;
import org.apache.http.client.methods.CloseableHttpResponse;
import org.apache.http.client.methods.HttpPost;
import org.apache.http.entity.ByteArrayEntity;
import org.apache.http.entity.ContentType;
import org.apache.http.impl.client.CloseableHttpClient;
import org.apache.http.impl.client.HttpClients;
import org.apache.http.util.EntityUtils;

/**
 * Wrapper around the CloudWatch Profiles query API — the Pyroscope-compatible {@code
 * querier.v1.QuerierService} surface served at {@code
 * https://monitoring.{region}.amazonaws.com/querier.v1.QuerierService/<Operation>}. Used to validate
 * profiles that an SDK profiler (e.g. the ADOT Java profiler) exported over OTLP to the CloudWatch
 * {@code /v1development/profiles} ingest endpoint.
 *
 * <p>Requests use the Connect JSON encoding ({@code Content-Type: application/json}); the response is
 * returned in the same encoding. Like {@link PromQLService}, requests are SigV4-signed with service
 * name {@code monitoring} via the {@link AWSRequestSigningApacheInterceptor}.
 */
@Log4j2
public class ProfilesService {
  private static final String SERVICE_NAME = "monitoring";
  private static final String QUERIER_PATH = "/querier.v1.QuerierService/";

  private final String baseEndpoint;
  private final CloseableHttpClient httpClient;
  private final ObjectMapper objectMapper = new ObjectMapper();

  /**
   * Construct the service for a region.
   *
   * @param region the AWS region (e.g. us-east-1)
   */
  public ProfilesService(String region) {
    this(region, null);
  }

  /**
   * Construct the service for a region, optionally assuming {@code roleArn} for the queries — e.g.
   * a role in an account enabled for CloudWatch Profiles when the caller's own account is not. The
   * profiles are then read from that role's account.
   *
   * @param region the AWS region (e.g. us-east-1)
   * @param roleArn role to assume, or null/empty to use the default credential chain
   */
  public ProfilesService(String region, String roleArn) {
    this.baseEndpoint = String.format("https://monitoring.%s.amazonaws.com", region);

    AWS4Signer signer = new AWS4Signer();
    signer.setServiceName(SERVICE_NAME);
    signer.setRegionName(region);
    AWSCredentialsProvider credentialsProvider =
        (roleArn == null || roleArn.isEmpty())
            ? new DefaultAWSCredentialsProviderChain()
            : new STSAssumeRoleSessionCredentialsProvider.Builder(roleArn, "profiles-validator")
                .withStsClient(
                    AWSSecurityTokenServiceClientBuilder.standard().withRegion(region).build())
                .build();
    this.httpClient =
        HttpClients.custom()
            .addInterceptorLast(
                new AWSRequestSigningApacheInterceptor(SERVICE_NAME, signer, credentialsProvider))
            .build();
  }

  /** {@code ProfileTypes}: every profile type ID ingested in the window. */
  public JsonNode profileTypes(long startMs, long endMs) throws Exception {
    ObjectNode body = objectMapper.createObjectNode();
    body.put("start", startMs);
    body.put("end", endMs);
    return call("ProfileTypes", body);
  }

  /** {@code LabelNames}: every label name on series matching {@code labelSelector}. */
  public JsonNode labelNames(String labelSelector, long startMs, long endMs) throws Exception {
    ObjectNode body = objectMapper.createObjectNode();
    body.putArray("matchers").add(labelSelector);
    body.put("start", startMs);
    body.put("end", endMs);
    return call("LabelNames", body);
  }

  /** {@code LabelValues}: every value of {@code labelName} on series matching {@code labelSelector}. */
  public JsonNode labelValues(String labelName, String labelSelector, long startMs, long endMs)
      throws Exception {
    ObjectNode body = objectMapper.createObjectNode();
    body.put("name", labelName);
    body.putArray("matchers").add(labelSelector);
    body.put("start", startMs);
    body.put("end", endMs);
    return call("LabelValues", body);
  }

  /**
   * {@code SelectMergeStacktraces}: the merged flame graph for one profile type. The response holds
   * {@code flamegraph.names} (every function name in the graph) and {@code flamegraph.total}.
   */
  public JsonNode selectMergeStacktraces(
      String profileTypeId, String labelSelector, long startMs, long endMs) throws Exception {
    ObjectNode body = objectMapper.createObjectNode();
    body.put("profile_typeID", profileTypeId);
    body.put("label_selector", labelSelector);
    body.put("start", startMs);
    body.put("end", endMs);
    return call("SelectMergeStacktraces", body);
  }

  /**
   * {@code SelectSeries}: one profile type's value over time, bucketed into {@code stepSeconds}
   * windows. The response holds {@code series[].points[]} ({@code value}, {@code timestamp} ms).
   */
  public JsonNode selectSeries(
      String profileTypeId, String labelSelector, long startMs, long endMs, double stepSeconds)
      throws Exception {
    ObjectNode body = objectMapper.createObjectNode();
    body.put("profile_typeID", profileTypeId);
    body.put("label_selector", labelSelector);
    body.put("start", startMs);
    body.put("end", endMs);
    body.put("step", stepSeconds);
    return call("SelectSeries", body);
  }

  private JsonNode call(String operation, ObjectNode body) throws Exception {
    String url = baseEndpoint + QUERIER_PATH + operation;
    String json = objectMapper.writeValueAsString(body);
    HttpPost post = new HttpPost(url);
    // The JSON body is signed verbatim by the interceptor. The Content-Type must be exactly
    // "application/json": the query API rejects a charset parameter (as ContentType.APPLICATION_JSON
    // would add) with HTTP 400 invalid_argument.
    post.setEntity(
        new ByteArrayEntity(
            json.getBytes(StandardCharsets.UTF_8), ContentType.create("application/json")));

    log.info("Calling CloudWatch Profiles {}: {}", operation, json);
    try (CloseableHttpResponse response = httpClient.execute(post)) {
      int status = response.getStatusLine().getStatusCode();
      String responseBody =
          response.getEntity() != null ? EntityUtils.toString(response.getEntity()) : "";
      if (status < 200 || status >= 300) {
        throw new RuntimeException(
            String.format(
                "CloudWatch Profiles %s failed: HTTP %d, body: %s",
                operation, status, responseBody));
      }
      return responseBody.isEmpty()
          ? objectMapper.createObjectNode()
          : objectMapper.readTree(responseBody);
    }
  }
}
