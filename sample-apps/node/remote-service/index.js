'use strict';

const express = require('express');

const PORT = parseInt(process.env.SAMPLE_APP_PORT || '8001', 10);

const app = express();

app.get('/healthcheck', (req, res) => {
  console.log(`/healthcheck (remote-service) called successfully`);
  res.send('/healthcheck (remote-service) called successfully');
});

app.listen(PORT, () => {
  console.log(`Listening for requests on http://localhost:${PORT}`);
});