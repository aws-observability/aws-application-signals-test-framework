'use strict';

const express = require('express');
const bunyan = require('bunyan');

const PORT = parseInt(process.env.SAMPLE_APP_PORT || '8001', 10);

const app = express();

// Create bunyan logger
const logger = bunyan.createLogger({name: 'remote-service', level: 'info'});

app.get('/healthcheck', (req, res) => {
  const msg = '/healthcheck (remote-service) called successfully';
  logger.info(msg);
  res.send(msg);
});

app.listen(PORT, () => {
  logger.info(`Listening for requests on http://localhost:${PORT}`);
});
