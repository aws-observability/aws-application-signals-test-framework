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
            Console.WriteLine("Starting thread");
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
