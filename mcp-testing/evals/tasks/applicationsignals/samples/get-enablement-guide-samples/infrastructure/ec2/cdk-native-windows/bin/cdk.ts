#!/usr/bin/env node
import * as cdk from 'aws-cdk-lib';
import { EC2NativeWindowsAppStack, AppConfig } from '../lib/cdk-stack';
import * as fs from 'fs';
import * as path from 'path';

const app = new cdk.App();

// Use account/region from environment or CLI config
const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION,
};

// Read all config files from config directory
const configDir = fs.realpathSync(path.resolve(__dirname, '../config'));
const configFiles = fs.readdirSync(configDir).filter(f => f.endsWith('.json'));

// Create a stack for each config
configFiles.forEach(configFile => {
  if (configFile.includes('..') || configFile.includes('/') || configFile.includes('\\')) {
    throw new Error(`Invalid config file name: ${configFile}`);
  }

  const configPath = path.join(configDir, configFile);
  const config: AppConfig = JSON.parse(fs.readFileSync(configPath, 'utf-8'));

  // Convert appName to PascalCase for stack ID (e.g., python-flask -> PythonFlask)
  const stackId = config.appName
    .split('-')
    .map(word => word.charAt(0).toUpperCase() + word.slice(1))
    .join('') + 'NativeStack';

  new EC2NativeWindowsAppStack(app, stackId, config, { env });
});

app.synth();