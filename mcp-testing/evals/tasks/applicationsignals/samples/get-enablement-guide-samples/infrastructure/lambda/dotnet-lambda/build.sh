#!/bin/bash

# Build .NET Lambda function
dotnet publish -c Release -o publish

# Create deployment package
cd publish
zip -r ../../builds/dotnet-lambda.zip .
cd ..

echo ".NET Lambda build complete"