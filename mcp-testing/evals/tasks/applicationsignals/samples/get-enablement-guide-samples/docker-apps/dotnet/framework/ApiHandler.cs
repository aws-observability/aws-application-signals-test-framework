// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading.Tasks;
using System.Web;
using Amazon.S3;
using Amazon.S3.Model;
using Newtonsoft.Json;

namespace FrameworkApp
{
    public class ApiHandler : IHttpHandler
    {
        public bool IsReusable => false;

        public void ProcessRequest(HttpContext context)
        {
            var path = context.Request.Path.ToLower();
            
            if (path.EndsWith("/api/buckets"))
            {
                ProcessBucketsRequest(context);
            }
            else
            {
                context.Response.StatusCode = 404;
                context.Response.Write("Not Found");
            }
        }

        private async void ProcessBucketsRequest(HttpContext context)
        {
            try
            {
                using (var s3Client = new AmazonS3Client())
                {
                    var response = await s3Client.ListBucketsAsync();
                    var buckets = response.Buckets.Select(b => b.BucketName).ToList();

                    var result = new
                    {
                        bucket_count = buckets.Count,
                        buckets = buckets
                    };

                    context.Response.ContentType = "application/json";
                    context.Response.Write(JsonConvert.SerializeObject(result));
                }
            }
            catch (Exception ex)
            {
                context.Response.StatusCode = 500;
                context.Response.ContentType = "application/json";
                context.Response.Write(JsonConvert.SerializeObject(new { error = "Failed to retrieve S3 buckets" }));
            }
        }
    }
}