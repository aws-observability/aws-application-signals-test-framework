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
         * Lambda function that performs S3 bucket operations.
         */
        Console.WriteLine("Starting Lambda execution");

        // Call buckets logic
        var bucketsResult = await ListBuckets();
        Console.WriteLine($"Buckets check: {bucketsResult["bucket_count"]} buckets found");

        return new Dictionary<string, object>
        {
            ["statusCode"] = 200,
            ["body"] = JsonSerializer.Serialize(new Dictionary<string, object>
            {
                ["message"] = "Execution completed",
                ["buckets"] = bucketsResult
            })
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