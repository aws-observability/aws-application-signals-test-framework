## Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
## SPDX-License-Identifier: Apache-2.0

# Use the official Node.js image as the base
FROM node:20-alpine

# Set working directory
WORKDIR /app

# Copy app to image
COPY . ./

# Install dependencies
RUN npm install

# Expose the port that the app will run on
EXPOSE 8001

# Command to start the application
CMD ["npm", "run", "start"]