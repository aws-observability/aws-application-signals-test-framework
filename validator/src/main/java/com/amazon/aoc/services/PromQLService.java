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

package com.amazon.aoc.services;

import com.amazonaws.auth.AWS4Signer;
import com.amazonaws.auth.AWSCredentialsProvider;
import com.amazonaws.auth.DefaultAWSCredentialsProviderChain;
import com.amazonaws.http.AWSRequestSigningApacheInterceptor;
import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import java.nio.charset.StandardCharsets;
import lombok.extern.log4j.Log4j2;
import org.apache.http.client.methods.CloseableHttpResponse;
import org.apache.http.client.methods.HttpPost;
import org.apache.http.entity.ContentType;
import org.apache.http.entity.StringEntity;
import org.apache.http.impl.client.CloseableHttpClient;
import org.apache.http.impl.client.HttpClients;
import org.apache.http.util.EntityUtils;

/**
 * Wrapper around the CloudWatch Prometheus-compatible query API
 * (https://monitoring.{region}.amazonaws.com/api/v1/query). Used to validate Service Events OTLP
 * metrics (`count` and `service.function.duration`), which are ingested as native OTLP metrics with
 * no fixed CloudWatch namespace and are therefore queried with PromQL rather than GetMetricData.
 *
 * <p>Requests are SigV4-signed with service name {@code monitoring} via the
 * {@link AWSRequestSigningApacheInterceptor}, which signs the fully-built Apache request immediately
 * before transmission (so the {@code Host} / {@code Content-Length} headers in the signature match
 * what is actually sent). The caller's role needs {@code cloudwatch:GetMetricData} and
 * {@code cloudwatch:ListMetrics}.
 */
@Log4j2
public class PromQLService {
  private static final String SERVICE_NAME = "monitoring";

  private final String queryEndpoint;
  private final CloseableHttpClient httpClient;
  private final ObjectMapper objectMapper = new ObjectMapper();

  /**
   * Construct the service for a region.
   *
   * @param region the AWS region (e.g. us-east-1)
   */
  public PromQLService(String region) {
    this.queryEndpoint = String.format("https://monitoring.%s.amazonaws.com/api/v1/query", region);

    AWS4Signer signer = new AWS4Signer();
    signer.setServiceName(SERVICE_NAME);
    signer.setRegionName(region);
    AWSCredentialsProvider credentialsProvider = new DefaultAWSCredentialsProviderChain();
    this.httpClient =
        HttpClients.custom()
            .addInterceptorLast(
                new AWSRequestSigningApacheInterceptor(SERVICE_NAME, signer, credentialsProvider))
            .build();
  }

  /**
   * Run an instant PromQL query and return the parsed Prometheus response. The returned node is the
   * top-level object containing {@code status} and {@code data.result}.
   *
   * @param promQlQuery the PromQL expression, e.g. {@code {"count", "@resource.service.name"="svc"}}
   * @return parsed JSON response
   * @throws Exception when the request fails or the response is not 2xx
   */
  public JsonNode query(String promQlQuery) throws Exception {
    HttpPost post = new HttpPost(queryEndpoint);
    // The form body is signed verbatim by the interceptor; the query is the single form field.
    String body = "query=" + urlEncode(promQlQuery);
    post.setEntity(
        new StringEntity(body, ContentType.create("application/x-www-form-urlencoded", "UTF-8")));

    log.info("Running PromQL query against {}: {}", queryEndpoint, promQlQuery);
    try (CloseableHttpResponse response = httpClient.execute(post)) {
      int status = response.getStatusLine().getStatusCode();
      String responseBody =
          response.getEntity() != null ? EntityUtils.toString(response.getEntity()) : "";
      if (status < 200 || status >= 300) {
        throw new RuntimeException(
            String.format("PromQL query failed: HTTP %d, body: %s", status, responseBody));
      }
      return objectMapper.readTree(responseBody);
    }
  }

  private static String urlEncode(String value) {
    try {
      return java.net.URLEncoder.encode(value, StandardCharsets.UTF_8.name());
    } catch (Exception e) {
      // UTF-8 is always supported; rethrow as unchecked to keep the signature clean.
      throw new RuntimeException(e);
    }
  }
}
