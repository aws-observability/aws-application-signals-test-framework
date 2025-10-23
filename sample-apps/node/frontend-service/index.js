'use strict';

const http = require('http');
const express = require('express');
const mysql = require('mysql2');
const bunyan = require('bunyan');
const { S3Client, GetBucketLocationCommand } = require('@aws-sdk/client-s3');
const { MeterProvider, PeriodicExportingMetricReader } = require('@opentelemetry/sdk-metrics');
const { OTLPMetricExporter } = require('@opentelemetry/exporter-otlp-grpc');
const { metrics } = require('@opentelemetry/api');
const { Resource } = require('@opentelemetry/resources');
const { randomInt } = require('crypto');

const PORT = parseInt(process.env.SAMPLE_APP_PORT || '8000', 10);

const app = express();

// Create bunyan logger
const logger = bunyan.createLogger({name: 'express-app', level: 'info'});

// Custom export pipeline - runs alongside existing CWAgent & ADOT setup
const pipelineResource = new Resource({
    'service.name': `node-sample-application-${process.env.TESTING_ID}`,
    'deployment.environment.name': 'ec2:default'
}));

const pipelineMetricExporter = new OTLPMetricExporter({
    endpoint: 'localhost:4317'
});

const pipelineMetricReader = new PeriodicExportingMetricReader({
    exporter: pipelineMetricExporter,
    exportIntervalMillis: 10000
});

const pipelineMeterProvider = new MeterProvider({
    resource: pipelineResource,
    readers: [pipelineMetricReader]
});

const pipelineMeter = pipelineMeterProvider.getMeter('myMeter');

const meter = metrics.getMeter('myMeter');
const agent_based_counter = meter.createCounter('agent_based_counter', {description: 'agent export counter'});
const agent_based_histogram = meter.createHistogram('agent_based_histogram', {description: 'agent export histogram'});
const agent_based_gauge = meter.createUpDownCounter('agent_based_gauge', {description: 'agent export gauge'});

const custom_pipeline_counter = pipelineMeter.createCounter('custom_pipeline_counter', {unit: '1', description: 'pipeline export counter'});
const custom_pipeline_histogram = pipelineMeter.createHistogram('custom_pipeline_histogram', {description: 'pipeline export histogram'});
const custom_pipeline_gauge = pipelineMeter.createUpDownCounter('custom_pipeline_gauge', {unit: '1', description: 'pipeline export gauge'});

app.get('/healthcheck', (req, res) => {
  logger.info('/healthcheck called successfully');
  res.send('healthcheck');
});

app.get('/outgoing-http-call', (req, res) => {
  const options = {
    hostname: 'www.amazon.com',
    method: 'GET',
  };

  const httpRequest = http.request(options, (rs) => {
    rs.setEncoding('utf8');
    rs.on('data', (result) => {
      const msg = '/outgoing-http-call called successfully';
      logger.info(msg);
      res.send(msg);
    });
    rs.on('error', (err) => {
      const msg = `/outgoing-http-call called with error: ${err}`;
      logger.error(msg);
      res.send(msg);
    });
  });
  httpRequest.end();
});

app.get('/aws-sdk-call', async (req, res) => {
  const s3Client = new S3Client({ region: 'us-east-1' });
  const bucketName = 'e2e-test-bucket-name-' + (req.query.testingId || 'MISSING_ID');

  // Increment counter/histogram/gauge for agent export
  agent_based_counter.add(1, { Operation : 'counter' });
  agent_based_histogram.record(randomInt(100,1001), { Operation : 'histogram' });
  agent_based_gauge.add(randomInt(-10, 11), { Operation : 'gauge' });

  // Increment counter/histogram/gauge for pipeline export
  custom_pipeline_counter.add(1, { Operation : 'pipeline_counter' });
  custom_pipeline_histogram.record(randomInt(100,1001), { Operation : 'pipeline_histogram' });
  custom_pipeline_gauge.add(randomInt(-10, 11), { Operation : 'pipeline_gauge' });

  // Add custom warning log for validation testing
  const warningMsg = "This is a custom log for validation testing";
  logger.warn(warningMsg);
  
  try {
    await s3Client.send(
      new GetBucketLocationCommand({
        Bucket: bucketName,
      }),
    ).then((data) => {
      const msg = '/aws-sdk-call called successfully; UNEXPECTEDLY RETURNED DATA: ' + data;
      logger.info(msg);
      res.send(msg);
    });
  } catch (e) {
    if (e instanceof Error) {
      const msg = '/aws-sdk-call called successfully';
      logger.info(msg);
      res.send(msg);
    }
  }
});

app.get('/remote-service', (req, res) => {
  const endpoint = req.query.ip || 'localhost';
  const options = {
    hostname: endpoint,
    port: 8001,
    method: 'GET',
    path: '/healthcheck'
  };

  const request = http.request(options, (rs) => {
    rs.setEncoding('utf8');
    rs.on('data', (result) => {
      const msg = `/remote-service called successfully: ${result}`;
      logger.info(msg);
      res.send(msg);
    });
  });
  request.on('error', (err) => {
    const msg = '/remote-service called with errors: ' + err.errors;
    logger.error(msg);
    res.send(msg);
  });
  request.end();
});

// The following logic serves as the async call made by the /client-call API
let makeAsyncCall = false;
setInterval(() => {
  if (makeAsyncCall) {
    makeAsyncCall = false;
    logger.info('Async call triggered by /client-call API');

    const request = http.get('http://local-root-client-call', (rs) => {
      rs.setEncoding('utf8');
      rs.on('data', (result) => {
        const msg = `GET local-root-client-call response: ${result}`;
        logger.info(msg);
        res.send(msg);
      });
    });
    request.on('error', (err) => {}); // Expected
    request.end();
  }
}, 5000); // Check every 5 seconds

app.get('/client-call', (req, res) => {
  const msg = '/client-call called successfully';
  logger.info(msg);
  res.send(msg);
  // Trigger async call to generate telemetry for InternalOperation use case
  makeAsyncCall = true;
});

app.get('/mysql', (req, res) => {
  // Create a connection to the MySQL database
  const connection = mysql.createConnection({
    host: process.env.RDS_MYSQL_CLUSTER_ENDPOINT,
    user: process.env.RDS_MYSQL_CLUSTER_USERNAME,
    password: process.env.RDS_MYSQL_CLUSTER_PASSWORD,
    database: process.env.RDS_MYSQL_CLUSTER_DATABASE,
  });

  // Connect to the database
  connection.connect((err) => {
    if (err) {
      const msg = '/mysql called with an error: ' + err.errors;
      logger.error(msg);
      return res.status(500).send(msg);
    }

    // Perform a simple query
    connection.query('SELECT * FROM tables LIMIT 1;', (queryErr, results) => {
      // Close the connection
      connection.end();

      if (queryErr) {
        const msg = 'Could not complete http request to RDS database:' + queryErr.message;
        logger.error(msg);
        return res.status(500).send(msg);
      }

      // Send the query results as the response
      const msg = `/outgoing-http-call response: ${results}`;
      logger.info(msg);
      res.send(msg);
    });
  });
});

app.listen(PORT, () => {
  logger.info(`Listening for requests on http://localhost:${PORT}`);
});