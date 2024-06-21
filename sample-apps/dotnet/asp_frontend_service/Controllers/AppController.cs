// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

using System;
using System.Diagnostics;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Amazon.S3;
using Microsoft.AspNetCore.Mvc;

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

    public AppController()
    {
        if (!threadStarted)
        {
            threadStarted = true;
            Thread thread = new Thread(() =>
            {
                while (true)
                {
                    if (shouldSendLocalRootClientCall)
                    {
                        shouldSendLocalRootClientCall = false;
                        try
                        {
                            _ = this.httpClient.GetAsync("http://local-root-client-call").Result;
                        }
                        catch (Exception)
                        {
                        }
                    }

                    Thread.Sleep(1000);
                }
            });

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
    public string AWSSDKCall()
    {
        _ = this.s3Client.ListBucketsAsync().Result;

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
        var endpoint = $"http://{ip}:8001/healthcheck";
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
