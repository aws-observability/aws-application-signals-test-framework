using System;
using System.Linq;
using System.Threading.Tasks;
using System.Web;
using Amazon;
using Amazon.S3;
using Amazon.S3.Model;
using Newtonsoft.Json;

namespace FrameworkApp
{
    // Change the base class to HttpTaskAsyncHandler
    public class ApiHandler : HttpTaskAsyncHandler
    {
        // HttpTaskAsyncHandler uses ProcessRequestAsync instead of ProcessRequest
        public override async Task ProcessRequestAsync(HttpContext context)
        {
            var path = context.Request.Path.ToLower();
            
            if (path.EndsWith("/api/buckets"))
            {
                await ProcessBucketsRequestAsync(context); // Await the async method
            }
            else
            {
                context.Response.StatusCode = 404;
                context.Response.Write("Not Found");
            }
        }

        private async Task ProcessBucketsRequestAsync(HttpContext context) // Make this method async Task
        {
            try
            {
                var awsRegion = Environment.GetEnvironmentVariable("AWS_REGION") ?? "us-east-1";
                var regionEndpoint = RegionEndpoint.GetBySystemName(awsRegion) ?? RegionEndpoint.USEast1;

                // Use 'await' instead of '.Result'
                using (var s3Client = new AmazonS3Client(regionEndpoint))
                {
                    var response = await s3Client.ListBucketsAsync();
                    // ... rest of the logic remains mostly the same ...
                    if (response == null) { throw new Exception("S3 response is null"); }
                    if (response.Buckets == null) { throw new Exception("S3 response.Buckets is null"); }

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
                // Your comprehensive error logging structure (works well for debugging)
                var innerException = ex.InnerException != null ? ex.InnerException.Message : "No inner exception";
                var errorDetails = new
                {
                    error = "Failed to retrieve S3 buckets",
                    details = ex.Message,
                    innerException = innerException,
                    type = ex.GetType().Name
                };
                context.Response.Write(JsonConvert.SerializeObject(errorDetails));
            }
        }

        // IHttpHandler requires IsReusable
        public bool IsReusable { get { return false; } }
    }
}
