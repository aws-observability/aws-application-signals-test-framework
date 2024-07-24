# Use the official lightweight Node.js 16 image.
# https://hub.docker.com/_/node
# FROM node:16-slim
FROM public.ecr.aws/eks-distro-build-tooling/nodejs:16

# Create and change to the app directory
WORKDIR /usr/src/app

# Copy application dependency manifests to the container image.
# A wildcard is used to ensure copying both package.json AND package-lock.json (if available).
# Copying this first prevents re-running npm install on every code change.
COPY package*.json ./

# Install dependencies
RUN npm install

# Copy local code to the container image.
COPY . .

# Run the web service on container startup.
CMD [ "npm", "start" ]
