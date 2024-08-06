const axios = require('axios');

// Send API requests to the sample app
const sendRequests = async (urls) => {
    try {
        const fetchPromises = urls.map(url => axios.get(url));
        const responses = await Promise.all(fetchPromises);

        // Handle the responses
        responses.forEach((response, index) => {
            if (response.status === 200) {
                const data = response.data;
                console.log(`Response from ${urls[index]}:`, data);
            } else {
                console.error(`Failed to fetch ${urls[index]}:`, response.statusText);
            }
        });
    } catch (error) {
        console.error('Error sending GET requests:', error);
    }
}

const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));

// This loop will run until the environment variables are available
const waitForEnvVariables = async () => {
    while (!process.env.MAIN_ENDPOINT || !process.env.REMOTE_ENDPOINT || !process.env.ID) {
        console.log('Environment variables not set. Waiting for 10 seconds...');
        await sleep(10000); // Wait for 10 seconds
    }
};

// Traffic generator that sends traffic every specified interval. Send request immediately then every 2 minutes afterwords
const trafficGenerator = async (interval) => {
    await waitForEnvVariables();

    const mainEndpoint = process.env.MAIN_ENDPOINT;
    const remoteEndpoint = process.env.REMOTE_ENDPOINT;
    const id = process.env.ID;

    let urls = [
        `http://${mainEndpoint}/outgoing-http-call`,
        `http://${mainEndpoint}/aws-sdk-call?ip=${remoteEndpoint}&testingId=${id}`,
        `http://${mainEndpoint}/remote-service?ip=${remoteEndpoint}&testingId=${id}`,
        `http://${mainEndpoint}/client-call`,
        `http://${mainEndpoint}/mysql`,
    ];

    await sendRequests(urls);
    setInterval(() => sendRequests(urls), interval);
}

const interval = 15 * 1000;
// Start sending GET requests every 15 seconds (60,000 milliseconds)
trafficGenerator(interval);