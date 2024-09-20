'use strict';

const http = require('http');
const express = require('express');
const mysql = require('mysql2');
const { S3Client, GetBucketLocationCommand } = require('@aws-sdk/client-s3');
const { BedrockAgentClient, ListPromptsCommand, ListAgentVersionsCommand, GetKnowledgeBaseCommand, GetDataSourceCommand } = require('@aws-sdk/client-bedrock-agent');
const { BedrockAgentRuntimeClient, InvokeAgentCommand, GetAgentMemoryCommand, RetrieveCommand } = require('@aws-sdk/client-bedrock-agent-runtime')
const { BedrockClient, GetGuardrailCommand } = require('@aws-sdk/client-bedrock');
const { BedrockRuntimeClient, InvokeModelCommand } = require('@aws-sdk/client-bedrock-runtime');

const PORT = parseInt(process.env.SAMPLE_APP_PORT || '8000', 10);

const app = express();

app.get('/healthcheck', (req, res) => {
  console.log(`/healthcheck called successfully`)
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

// done
app.get('/bedrock-agent', async (req, res) => {
  const bedrockAgentClient = new BedrockAgentClient({ region: 'us-east-1' });
  try {
    const resp = await bedrockAgentClient.send(new ListPromptsCommand({}));

    // Decode the response body
    // const decoder = new TextDecoder('utf-8');
    // const decodedResponseBody = decoder.decode(resp);
    const log = `
=================================================
/bedrock-agent called successfully!
Response - First prompt in the list for ListPromptsCommand: ${JSON.stringify(resp.promptSummaries[0], null, 2)}
=================================================`
    console.log(log);
    res.send(log);
  } catch (e) {
    if (e instanceof Error) {
      const log = `
=================================================
/bedrock-agent call failed: ${e.message}
=================================================`
      console.log(log);
      res.send(log);
    }
  }
});

// done
app.get('/bedrock-agent-agent-operation', async (req, res) => {
  const bedrockAgentClient = new BedrockAgentClient({ region: 'us-east-1' });
  try {
    const resp = await bedrockAgentClient.send(new ListAgentVersionsCommand({ agentId: 'JMVCQS1RBJ'}));

    // Decode the response body
    // const decoder = new TextDecoder('utf-8');
    // const decodedResponseBody = decoder.decode(resp);
    const log = `
=================================================
/bedrock-agent-agent-operation called successfully!
Response - First agent version in the list for ListAgentVersionsCommand: ${JSON.stringify(resp.agentVersionSummaries[0], null, 2)}
=================================================`
    console.log(log);
    res.send(log);
  } catch (e) {
    if (e instanceof Error) {
      const log = `
=================================================
/bedrock-agent-agent-operation call failed: ${e.message}
=================================================`
      console.log(log);
      res.send(log);
    }
  }
});

// done
app.get('/bedrock-agent-knowledge-base-operation', async (req, res) => {
  const bedrockAgentClient = new BedrockAgentClient({ region: 'us-east-1' });
  try {
    const resp = await bedrockAgentClient.send(new GetKnowledgeBaseCommand({ knowledgeBaseId: 'D9UMGXCCZJ' }));

    // Decode the response body
    // const decoder = new TextDecoder('utf-8');
    // const decodedResponseBody = decoder.decode(resp);
    const log = `
=================================================
/bedrock-agent-knowledge-base-operation called successfully!
Response - Knowledge base name for GetKnowledgeBaseCommand({ knowledgeBaseId: 'D9UMGXCCZJ' }): ${JSON.stringify(resp.knowledgeBase.name, null, 2)}
=================================================`
    console.log(log);
    res.send(log);
  } catch (e) {
    if (e instanceof Error) {
      const log = `
=================================================
/bedrock-agent-knowledge-base-operation call failed: ${e.message}
=================================================`
      console.log(log);
      res.send(log);
    }
  }
});

// done
app.get('/bedrock-agent-data-source-operation', async (req, res) => {
  const bedrockAgentClient = new BedrockAgentClient({ region: 'us-east-1' });
  try {
    const resp = await bedrockAgentClient.send(new GetDataSourceCommand({ knowledgeBaseId: 'D9UMGXCCZJ', dataSourceId: 'XQDUXSYBHD' }));

    // Decode the response body
    // const decoder = new TextDecoder('utf-8');
    // const decodedResponseBody = decoder.decode(resp);
    const log = `
=================================================
/bedrock-agent-data-source-operation called successfully!
Response - Data source name for GetDataSourceCommand: ${JSON.stringify(resp.dataSource.name, null, 2)}
=================================================`
    console.log(log);
    res.send(log);
  } catch (e) {
    if (e instanceof Error) {
      const log = `
=================================================
/bedrock-agent-data-source-operation call failed: ${e.message}
=================================================`
      console.log(log);
      res.send(log);
    }
  }
});

// done
app.get('/bedrock-agent-runtime', async (req, res) => {
  const bedrockAgentRuntimeClient = new BedrockAgentRuntimeClient({ region: 'us-east-1' });
  try {
    const resp = await bedrockAgentRuntimeClient.send(new RetrieveCommand({ knowledgeBaseId: 'D9UMGXCCZJ', retrievalQuery: { text: 'query' } }));

    // Decode the response body
    // const decoder = new TextDecoder('utf-8');
    // const decodedResponseBody = decoder.decode(resp);
    const log = `
=================================================
/bedrock-agent-runtime called successfully!
Response - Full response for RetrieveCommand: ${JSON.stringify(resp, null, 2)}
=================================================`
    console.log(log);
    res.send(log);
  } catch (e) {
    if (e instanceof Error) {
      const log = `
=================================================
/bedrock-agent-runtime call failed: ${e.message}
=================================================`
      console.log(log);
      res.send(log);
    }
  }
});

// done
app.get('/bedrock', async (req, res) => {
  const bedrockClient = new BedrockClient({ region: 'us-east-1' });
  try {
    const resp = await bedrockClient.send(new GetGuardrailCommand({ guardrailIdentifier: 'yalzttk80hfi' }));

    // Decode the response body
    // const decoder = new TextDecoder('utf-8');
    // const decodedResponseBody = decoder.decode(resp);
    const log = `
=================================================
/bedrock called successfully!
Response - Full response from GetGuardrailCommand: ${JSON.stringify(resp, null, 2)}
=================================================`
    console.log(log);
    res.send(log);
  } catch (e) {
    if (e instanceof Error) {
      const log = `
=================================================
/bedrock call failed: ${e.message}
=================================================`
      console.log(log);
      res.send(log);
    }
  }
});

// done
app.get('/bedrock-runtime', async (req, res) => {
  const bedrockRuntimeClient = new BedrockRuntimeClient({ region: 'us-east-1' });
  const prompt = 'Write me a small haiku about working at AWS'
  const input = {
    modelId:"amazon.titan-text-lite-v1",
    contentType:"application/json",
    accept:"application/json",
    body: JSON.stringify({
      inputText:prompt,
      textGenerationConfig: {
        maxTokenCount: 512
      }
    })
  };
  try {
    const command = new InvokeModelCommand(input);
    const resp = await bedrockRuntimeClient.send(command)

    // Decode the response body
    const decoder = new TextDecoder('utf-8');
    const decodedResponseBody = JSON.stringify(JSON.parse(decoder.decode(resp.body)), null, 2);
    const log = `
=================================================
/bedrock-runtime called successfully!
Response: ${decodedResponseBody}
=================================================`
    console.log(log);
    res.send(log);
  } catch (e) {
    if (e instanceof Error) {
      const log = `
=================================================
/bedrock-runtime call failed: ${e.message}
=================================================`
      console.log(log)
      res.send(log);
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
      console.log(`/remote-service called successfully: ${result}`);
      res.send(`/remote-service called successfully: ${result}`);
    });
  });
  request.on('error', (err) => {
    console.log('/remote-service called with errors: ' + err.errors);
    res.send('/remote-service called with errors: ' + err.errors);
  })
  request.end();
});

// The following logic serves as the async call made by the /client-call API
let makeAsyncCall = false;
setInterval(() => {
  if (makeAsyncCall) {
    makeAsyncCall = false;
    console.log('Async call triggered by /client-call API');

    const request = http.get('http://local-root-client-call', (rs) => {
      rs.setEncoding('utf8');
      rs.on('data', (result) => {
        res.send(`GET local-root-client-call response: ${result}`);
      });
    });
    request.on('error', (err) => {}); // Expected
    request.end();
  }
}, 5000); // Check every 5 seconds

app.get('/client-call', (req, res) => {
  res.send('/client-call called successfully');
  console.log('/client-call called successfully');

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

app.listen(PORT, () => {
  console.log(`Listening for requests on http://localhost:${PORT}`);
});