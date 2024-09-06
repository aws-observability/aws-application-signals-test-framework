const AWSXRay = require('aws-xray-sdk');
const XRayExpress = AWSXRay.express;
const express = require('express');

// Capture all AWS clients we create
const AWS = AWSXRay.captureAWS(require('aws-sdk'));
AWS.config.update({region: process.env.DEFAULT_AWS_REGION || 'us-west-2'});

// Capture all outgoing https requests
AWSXRay.captureHTTPsGlobal(require('https'));
const http = require('http');

// Capture MySQL queries
const mysql = AWSXRay.captureMySQL(require('mysql'));
const { S3Client, GetBucketLocationCommand } = require('@aws-sdk/client-s3');


const app = express();
const PORT = parseInt(process.env.SAMPLE_APP_PORT || '8000', 10);

app.use(XRayExpress.openSegment('SampleSite'));
app.get('/healthcheck', (req, res) => {
  const seg = AWSXRay.getSegment();
  const sub = seg.addNewSubsegment('customSubsegment');
  setTimeout(() => {
    sub.close();
    console.log(`/healthcheck called successfully`)
    res.send('healthcheck');
  }, 500);
});

app.get('/outgoing-http-call', (req, res) => {
  const options = {
    hostname: 'www.amazon.com',
    method: 'GET',
  };

  const httpRequest = http.request(options, (rs) => {
    rs.setEncoding('utf8');
    rs.on('data', (result) => {
      console.log(`/outgoing-http-call called successfully`)
      res.send(`/outgoing-http-call called successfully`);
    });
    rs.on('error', (err) => {
      console.log(`/outgoing-http-call called with error: ${err}`)
      res.send(`/outgoing-http-call called with error: ${err}`);
    });
  });
  httpRequest.end();
});

app.get('/aws-sdk-call', async (req, res) => {
  const s3Client = new S3Client({ region: 'us-east-1' });
  const bucketName = 'e2e-test-bucket-name-' + (req.query.testingId || 'MISSING_ID');
  try {
    await s3Client.send(
        new GetBucketLocationCommand({
          Bucket: bucketName,
        }),
    ).then((data) => {
      console.log('/aws-sdk-call called successfully; UNEXPECTEDLY RETURNED DATA: ' + data);
      res.send('/aws-sdk-call called successfully; UNEXPECTEDLY RETURNED DATA: ' + data);
    });
  } catch (e) {
    if (e instanceof Error) {
      console.log('/aws-sdk-call called successfully')
      res.send('/aws-sdk-call called successfully');
    }
  }
});

app.get('/client-call', (req, res) => {
  // Immediately respond to the client without waiting for the HTTP request to complete
  res.status(202).send('/client-call called successfully');
  console.log('/client-call called successfully')

  const request = http.get('http://local-root-client-call', (rs) => {
    rs.setEncoding('utf8');
    rs.on('data', (result) => {
      res.send(`/client-call response: ${result}`);
    });
  });
  request.on('error', (err) => {});
  request.end();
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
      console.log('/mysql called with an error: ', err.errors);
      return res.status(500).send('/mysql called with an error: ' + err.errors);
    }

    // Perform a simple query
    connection.query('SELECT * FROM tables LIMIT 1;', (queryErr, results) => {
      // Close the connection
      connection.end();

      if (queryErr) {
        return res.status(500).send('Could not complete http request to RDS database:' + queryErr.message);
      }

      // Send the query results as the response
      res.send(`/outgoing-http-call response: ${results}`);
    });
  });
});

app.use(XRayExpress.closeSegment());

app.listen(PORT, () => {
  console.log(`Listening for requests on http://localhost:${PORT}`);
});