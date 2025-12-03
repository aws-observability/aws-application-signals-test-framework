// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

using System;
using System.Diagnostics;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Amazon.S3;
using Microsoft.AspNetCore.Mvc;
using Amazon.S3.Model;
using System.Diagnostics.Metrics;
using System.Collections.Generic;
using OpenTelemetry;
using OpenTelemetry.Metrics;
using OpenTelemetry.Resources;
using OpenTelemetry.Exporter;

namespace asp_frontend_service.Controllers;

[ApiController]
[Route("[controller]")]
public class AppController : ControllerBase
{
    // reads and writes to bool are atomic according to spec:
    // https://learn.microsoft.com/en-us/dotnet/csharp/language-reference/language-specification/variables#96-atomicity-of-variable-references
    private static bool shouldSendLocalRootClientCall = false;
    private static bool threadStarted = false;
    private readonly AmazonS3Client s3Client = new AmazonS3Client();
    private readonly HttpClient httpClient = new HttpClient();
    private static readonly Meter meter = new Meter("myMeterSource");
    private static readonly Counter<int> agentBasedCounter;
    private static readonly Histogram<double> agentBasedHistogram;
    private static readonly UpDownCounter<int> agentBasedGauge;

    // Custom pipeline metrics - only create if specific env vars exist
    private static readonly Meter pipelineMeter;
    private static readonly Counter<int> customPipelineCounter;
    private static readonly Histogram<double> customPipelineHistogram;
    private static readonly UpDownCounter<int> customPipelineGauge;
    private static readonly MeterProvider pipelineMeterProvider;

    static AppController()
    {

        agentBasedCounter = meter.CreateCounter<int>("agent_based_counter");
        agentBasedHistogram = meter.CreateHistogram<double>("agent_based_histogram");
        agentBasedGauge = meter.CreateUpDownCounter<int>("agent_based_gauge");
        
        var serviceName = Environment.GetEnvironmentVariable("SERVICE_NAME");
        var deploymentEnv = Environment.GetEnvironmentVariable("DEPLOYMENT_ENVIRONMENT_NAME");
        
        if (!string.IsNullOrEmpty(serviceName) && !string.IsNullOrEmpty(deploymentEnv))
        {
            
            pipelineMeterProvider = Sdk.CreateMeterProviderBuilder()
                .SetResourceBuilder(ResourceBuilder.CreateDefault().AddAttributes(new Dictionary<string, object>
                {
                    ["service.name"] = serviceName
                }))
                .AddOtlpExporter(options =>
                {
                    options.Endpoint = new Uri("http://localhost:4318/v1/metrics");
                    options.Protocol = OtlpExportProtocol.HttpProtobuf;
                    options.ExportProcessorType = ExportProcessorType.Batch;
                })
                .AddReader(new PeriodicExportingMetricReader(new OtlpMetricExporter(new OtlpExporterOptions
                {
                    Endpoint = new Uri("http://localhost:4318/v1/metrics"),
                    Protocol = OtlpExportProtocol.HttpProtobuf
                }), 1000))
                .AddMeter("myMeter")
                .Build();
            
            pipelineMeter = new Meter("myMeter");
            customPipelineCounter = pipelineMeter.CreateCounter<int>("custom_pipeline_counter", "1", "pipeline export counter");
            customPipelineHistogram = pipelineMeter.CreateHistogram<double>("custom_pipeline_histogram", "ms", "pipeline export histogram");
            customPipelineGauge = pipelineMeter.CreateUpDownCounter<int>("custom_pipeline_gauge", "1", "pipeline export gauge");
        }
    }

    private static readonly Thread thread = new Thread(() =>
            {
                while (true)
                {
                    if (shouldSendLocalRootClientCall)
                    {
                        try
                        {
                            shouldSendLocalRootClientCall = false;
                            // forcing the new activity to not have a parent and thus become a local root span
                            Activity.Current = null;
                            var localHttpClient = new HttpClient();
                            _ = localHttpClient.GetAsync("http://local-root-client-call").Result;
                        }
                        catch (Exception)
                        {
                        }
                    }

                    Thread.Sleep(500);
                }
            });

    public AppController()
    {
        if (!threadStarted)
        {
            threadStarted = true;
            thread.Start();
        }
    }

    [HttpGet]
    [Route("/outgoing-http-call")]
    public string OutgoingHttp()
    {
        _ = this.httpClient.GetAsync("https://aws.amazon.com").Result;

        return this.GetTraceId();
    }

    [HttpGet]
    [Route("/aws-sdk-call")]
    public string AWSSDKCall([FromQuery] string testingId)
    {
        var random = new Random();
        
        // Agent-based metrics
        agentBasedCounter.Add(1, new KeyValuePair<string, object?>("Operation", "counter"));
        agentBasedHistogram.Record(random.NextDouble() * 100, new KeyValuePair<string, object?>("Operation", "histogram"));
        agentBasedGauge.Add(random.Next(-10, 11), new KeyValuePair<string, object?>("Operation", "gauge"));
        
        // Pipeline metrics
        if (customPipelineCounter != null)
        {
            customPipelineCounter.Add(1, new KeyValuePair<string, object?>("Operation", "pipeline_counter"));
            customPipelineHistogram?.Record(random.Next(100, 1001), new KeyValuePair<string, object?>("Operation", "pipeline_histogram"));
            customPipelineGauge?.Add(random.Next(-10, 11), new KeyValuePair<string, object?>("Operation", "pipeline_gauge"));
        }
        
        
        var bucketName = "e2e-test-bucket-name";
        if (!string.IsNullOrEmpty(testingId))
        {
            bucketName += "-" + testingId;
        }
        
        var request = new GetBucketLocationRequest()
            {
               BucketName = testingId
            };
        _ = this.s3Client.GetBucketLocationAsync(request).Result;

        return this.GetTraceId();
    }

    [HttpGet]
    [Route("/client-call")]
    public string AsyncCall()
    {
        shouldSendLocalRootClientCall = true;
        return "{\"traceId\": \"1-00000000-000000000000000000000000\"}";
    }

    [HttpGet]
    [Route("/remote-service")]
    public string RemoteServiceCall([FromQuery(Name = "ip")] string ip)
    {
        var endpoint = $"http://{ip}:8081/healthcheck";
        _ = this.httpClient.GetAsync(endpoint).Result;

        return this.GetTraceId();
    }

    [HttpGet]
    [Route("/")]
    public string Default()
    {
        return "Application started!";
    }

    private string GetTraceId()
    {
        var traceId = Activity.Current.TraceId.ToHexString();
        var version = "1";
        var epoch = traceId.Substring(0, 8);
        var random = traceId.Substring(8);
        return "{" + "\"traceId\"" + ": " + "\"" + version + "-" + epoch + "-" + random + "\"" + "}";
    }
}
