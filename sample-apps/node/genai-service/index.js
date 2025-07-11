const express = require('express');
const { BedrockChat } = require("@langchain/community/chat_models/bedrock");
const { ChatPromptTemplate } = require("@langchain/core/prompts");
const traceloop = require("@traceloop/node-server-sdk")
const logger = require('pino')()

const app = express();
app.use(express.json());
const PORT = parseInt(process.env.SAMPLE_APP_PORT || '8000', 10);

const llm = new BedrockChat({
    model: "anthropic.claude-3-sonnet-20240229-v1:0",
    region: "us-east-1",
    credentials: {
        accessKeyId: process.env.BEDROCK_AWS_ACCESS_KEY_ID,
        secretAccessKey: process.env.BEDROCK_AWS_SECRET_ACCESS_KEY,
    },
    temperature: 0.7,
});

const prompt = ChatPromptTemplate.fromMessages([
    [
      "system",
      "You are a helpful assistant. Provide a helpful response to the following user input.",
    ],
    ["human", "{input}"],
  ]);

const chain = prompt.pipe(llm);

app.get('/health', (req, res) => {
    res.json({ status: 'healthy' });
});

app.post('/ai-chat', async (req, res) => {
    const { message } = req.body;
    
    if (!message) {
        return res.status(400).json({ error: 'Message is required' });
    }

    try {
        logger.info(`Question asked: ${message}`);
        
        const response = await traceloop.withWorkflow({ name: "sample_chat" }, () => {
            return traceloop.withTask({ name: "parent_task" }, () => {
                return chain.invoke({
                    input_language: "English",
                    output_language: "English",
                    input: message,
                });
            });
        });
        
        res.json({ response: response.content });
    } catch (error) {
        logger.error(`Error processing request: ${error.message}`);
        res.status(500).json({ error: 'Internal server error' });
    }
});

app.listen(PORT, () => {
    logger.info(`GenAI service listening on port ${PORT}`);
});