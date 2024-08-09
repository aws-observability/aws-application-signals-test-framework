// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: Apache-2.0

using System;
using System.Diagnostics;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;

namespace asp_remote_service.Controllers;

[ApiController]
[Route("[controller]")]
public class AppController : ControllerBase
{
    [HttpGet]
    [Route("/")]
    public string Default()
    {
        return "Application started!";
    }

    [HttpGet]
    [Route("/healthcheck")]
    public string HealthCheck()
    {
        return "Remote service healthcheck!";
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
