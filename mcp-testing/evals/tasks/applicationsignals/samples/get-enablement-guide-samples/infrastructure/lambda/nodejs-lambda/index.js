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

const { S3Client, ListBucketsCommand } = require('@aws-sdk/client-s3');

const s3 = new S3Client({});

exports.handler = async (event, context) => {
    /**
     * Lambda function that performs S3 bucket operations.
     */
    console.log('Starting Lambda execution');

    // Call buckets logic
    const bucketsResult = await listBuckets();
    console.log(`Buckets check: ${bucketsResult.bucket_count} buckets found`);

    return {
        statusCode: 200,
        body: JSON.stringify({
            message: 'Execution completed',
            buckets: bucketsResult
        })
    };
};

async function listBuckets() {
    /**
     * List S3 buckets logic.
     */
    try {
        const result = await s3.send(new ListBucketsCommand({}));
        const bucketCount = result.Buckets ? result.Buckets.length : 0;

        return { bucket_count: bucketCount, message: `Found ${bucketCount} buckets` };
    } catch (error) {
        console.error('Error listing buckets:', error);
        return { bucket_count: 0, message: 'Error listing buckets' };
    }
}