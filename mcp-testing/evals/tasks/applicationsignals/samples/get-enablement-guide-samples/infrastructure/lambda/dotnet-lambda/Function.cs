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

using Amazon.Lambda.Core;
using Amazon.S3;
using Amazon.S3.Model;
using System.Text.Json;

[assembly: LambdaSerializer(typeof(Amazon.Lambda.Serialization.SystemTextJson.DefaultLambdaJsonSerializer))]

namespace DotnetLambda;

public class Function
{
    private readonly IAmazonS3 _s3Client = new AmazonS3Client();

    public async Task<Dictionary<string, object>> FunctionHandler(Dictionary<string, object> input, ILambdaContext context)
    {
        /**
         * Self-contained Lambda function that generates internal traffic.
         * 
         * Runs for ~10 minutes, calling application functions in a loop.
         */
        Console.WriteLine("Starting self-contained traffic generation");

        int duration = 600; // Run for 10 minutes (600 seconds)
        int interval = 2; // Call every 2 seconds

        var startTime = DateTime.Now;
        int iteration = 0;

        while ((DateTime.Now - startTime).TotalSeconds < duration)
        {
            iteration++;
            string timestamp = DateTime.Now.ToString("HH:mm:ss");

            Console.WriteLine($"[{timestamp}] Iteration {iteration}: Generating traffic...");

            // Call buckets logic
            var bucketsResult = await ListBuckets();
            Console.WriteLine($"[{timestamp}] Buckets check: {bucketsResult["bucket_count"]} buckets found");

            // Sleep between requests
            await Task.Delay(interval * 1000);
        }

        double elapsed = (DateTime.Now - startTime).TotalSeconds;
        Console.WriteLine($"Traffic generation completed. Total iterations: {iteration}, Elapsed time: {elapsed:F2}s");

        return new Dictionary<string, object>
        {
            ["statusCode"] = 200,
            ["body"] = new Dictionary<string, object>
            {
                ["message"] = "Traffic generation completed",
                ["iterations"] = iteration,
                ["elapsed_seconds"] = elapsed
            }
        };
    }

    private async Task<Dictionary<string, object>> ListBuckets()
    {
        /**
         * List S3 buckets logic.
         */
        try
        {
            var response = await _s3Client.ListBucketsAsync();
            int bucketCount = response.Buckets.Count;

            return new Dictionary<string, object>
            {
                ["bucket_count"] = bucketCount,
                ["message"] = $"Found {bucketCount} buckets"
            };
        }
        catch (Exception ex)
        {
            Console.WriteLine($"Error listing buckets: {ex.Message}");
            return new Dictionary<string, object>
            {
                ["bucket_count"] = 0,
                ["message"] = "Error listing buckets"
            };
        }
    }
}