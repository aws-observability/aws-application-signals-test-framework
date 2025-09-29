'use strict';

const http = require('http');
const express = require('express');
const mysql = require('mysql2');
const bunyan = require('bunyan');
const { S3Client, GetBucketLocationCommand } = require('@aws-sdk/client-s3');
const { Signer } = require('@aws-sdk/rds-signer');

const PORT = parseInt(process.env.SAMPLE_APP_PORT || '8000', 10);

const app = express();

// Create bunyan logger
const logger = bunyan.createLogger({name: 'express-app', level: 'info'});

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

app.get('/mysql', async (req, res) => {
  try {
    const region = process.env.AWS_REGION || process.env.AWS_DEFAULT_REGION || 'us-east-1';
    const signer = new Signer({
      region: region,
      hostname: process.env.RDS_MYSQL_CLUSTER_ENDPOINT,
      port: 3306,
      username: process.env.RDS_MYSQL_CLUSTER_USERNAME
    });
    const token = await signer.getAuthToken();

    // Create a connection to the MySQL database using IAM authentication
    const connection = mysql.createConnection({
      host: process.env.RDS_MYSQL_CLUSTER_ENDPOINT,
      user: process.env.RDS_MYSQL_CLUSTER_USERNAME,
      password: token,
      database: process.env.RDS_MYSQL_CLUSTER_DATABASE,
      ssl: 'Amazon RDS',
      authPlugins: {
        mysql_clear_password: () => () => Buffer.from(token + '\0')
      }
    });

    // Connect to the database
    connection.connect((err) => {
      if (err) {
        const msg = '/mysql called with an error: ' + err.message;
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
        const msg = `/mysql response: ${JSON.stringify(results)}`;
        logger.info(msg);
        res.send(msg);
      });
    });
  } catch (error) {
    const msg = '/mysql called with IAM token generation error: ' + error.message;
    logger.error(msg);
    res.status(500).send(msg);
  }
});

app.listen(PORT, () => {
  logger.info(`Listening for requests on http://localhost:${PORT}`);
});