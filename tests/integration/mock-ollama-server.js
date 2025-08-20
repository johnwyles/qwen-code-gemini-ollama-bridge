#!/usr/bin/env node

/**
 * Mock Ollama Server for Integration Testing
 * 
 * This server mimics an Ollama API endpoint for testing qwen-code CLI
 * with and without the Gemini-OpenAI bridge. It logs all requests
 * for validation and returns appropriate mock responses.
 */

const express = require('express');
const fs = require('fs');
const path = require('path');

class MockOllamaServer {
    constructor(port = 8443, logFile = '/tmp/mock-ollama-requests.log') {
        this.port = port;
        this.logFile = logFile;
        this.app = express();
        this.server = null;
        this.requests = [];
        
        this.setupMiddleware();
        this.setupRoutes();
    }
    
    setupMiddleware() {
        // Parse JSON requests
        this.app.use(express.json({ limit: '50mb' }));
        
        // Log all requests
        this.app.use((req, res, next) => {
            const timestamp = new Date().toISOString();
            const logEntry = {
                timestamp,
                method: req.method,
                url: req.url,
                headers: req.headers,
                body: req.body,
                query: req.query
            };
            
            this.requests.push(logEntry);
            
            // Write to log file
            fs.appendFileSync(this.logFile, JSON.stringify(logEntry) + '\n');
            
            console.log(`[${timestamp}] ${req.method} ${req.url}`);
            if (req.body && Object.keys(req.body).length > 0) {
                console.log('  Body:', JSON.stringify(req.body, null, 2));
            }
            
            next();
        });
    }
    
    setupRoutes() {
        // Health check
        this.app.get('/health', (req, res) => {
            res.json({
                status: 'healthy',
                server: 'mock-ollama',
                uptime: process.uptime(),
                requestCount: this.requests.length
            });
        });
        
        // Models endpoint
        this.app.get('/v1/models', (req, res) => {
            res.json({
                object: 'list',
                data: [
                    {
                        id: 'qwen3-coder:latest',
                        object: 'model',
                        created: Math.floor(Date.now() / 1000),
                        owned_by: 'ollama'
                    },
                    {
                        id: 'qwen3-coder:7b',
                        object: 'model',
                        created: Math.floor(Date.now() / 1000),
                        owned_by: 'ollama'
                    }
                ]
            });
        });
        
        // Chat completions endpoint
        this.app.post('/v1/chat/completions', (req, res) => {
            const { model, messages, max_tokens, temperature, stream } = req.body;
            
            // Validate this is proper OpenAI format
            const hasGeminiFields = !!(
                req.body.generationConfig ||
                req.body.safetySettings ||
                req.body.tools ||
                req.body.toolConfig ||
                req.body.systemInstruction
            );
            
            // Flag for test validation
            if (hasGeminiFields) {
                console.log('⚠️  WARNING: Received Gemini-format request (bridge may not be working)');
            } else {
                console.log('✅ Received clean OpenAI-format request');
            }
            
            // Check for excessive token requests
            if (max_tokens && max_tokens > 50000) {
                console.log('⚠️  WARNING: Excessive token request:', max_tokens);
            }
            
            const response = {
                id: 'chatcmpl-test-' + Date.now(),
                object: 'chat.completion',
                created: Math.floor(Date.now() / 1000),
                model: model || 'qwen3-coder:latest',
                choices: [{
                    index: 0,
                    message: {
                        role: 'assistant',
                        content: `Mock response from Ollama server. Request format: ${hasGeminiFields ? 'GEMINI' : 'OPENAI'}`
                    },
                    finish_reason: 'stop'
                }],
                usage: {
                    prompt_tokens: messages ? messages.reduce((acc, msg) => acc + msg.content.length / 4, 0) : 10,
                    completion_tokens: 15,
                    total_tokens: 25
                }
            };
            
            res.json(response);
        });
        
        // Catch-all for other endpoints
        this.app.all('*', (req, res) => {
            console.log(`⚠️  Unhandled endpoint: ${req.method} ${req.url}`);
            res.status(404).json({
                error: {
                    message: `Endpoint not found: ${req.method} ${req.url}`,
                    type: 'not_found',
                    param: null,
                    code: 'endpoint_not_found'
                }
            });
        });
    }
    
    start() {
        return new Promise((resolve, reject) => {
            this.server = this.app.listen(this.port, '0.0.0.0', (err) => {
                if (err) {
                    reject(err);
                } else {
                    console.log(`🚀 Mock Ollama server running on port ${this.port}`);
                    console.log(`📝 Logging requests to: ${this.logFile}`);
                    resolve();
                }
            });
        });
    }
    
    stop() {
        return new Promise((resolve) => {
            if (this.server) {
                this.server.close(() => {
                    console.log('🛑 Mock Ollama server stopped');
                    resolve();
                });
            } else {
                resolve();
            }
        });
    }
    
    getRequests() {
        return this.requests;
    }
    
    clearRequests() {
        this.requests = [];
        if (fs.existsSync(this.logFile)) {
            fs.unlinkSync(this.logFile);
        }
    }
    
    getLastRequest() {
        return this.requests[this.requests.length - 1];
    }
    
    validateRequestFormat(expectedFormat = 'openai') {
        const lastRequest = this.getLastRequest();
        if (!lastRequest || !lastRequest.body) {
            return { valid: false, error: 'No request found' };
        }
        
        const body = lastRequest.body;
        const hasGeminiFields = !!(
            body.generationConfig ||
            body.safetySettings ||
            body.tools ||
            body.toolConfig ||
            body.systemInstruction
        );
        
        if (expectedFormat === 'openai' && hasGeminiFields) {
            return { 
                valid: false, 
                error: 'Expected OpenAI format but received Gemini fields',
                geminiFields: Object.keys(body).filter(key => 
                    ['generationConfig', 'safetySettings', 'tools', 'toolConfig', 'systemInstruction'].includes(key)
                )
            };
        }
        
        if (expectedFormat === 'gemini' && !hasGeminiFields) {
            return { 
                valid: false, 
                error: 'Expected Gemini format but received pure OpenAI format'
            };
        }
        
        // Check token limits
        const tokenIssues = [];
        if (body.max_tokens && body.max_tokens > 50000) {
            tokenIssues.push(`Excessive max_tokens: ${body.max_tokens}`);
        }
        
        return { 
            valid: true, 
            format: hasGeminiFields ? 'gemini' : 'openai',
            tokenIssues,
            request: body
        };
    }
}

// CLI interface when run directly
if (require.main === module) {
    const port = process.env.MOCK_PORT || 8443;
    const logFile = process.env.MOCK_LOG_FILE || '/tmp/mock-ollama-requests.log';
    
    const server = new MockOllamaServer(port, logFile);
    
    // Handle graceful shutdown
    process.on('SIGTERM', async () => {
        console.log('Received SIGTERM, shutting down gracefully...');
        await server.stop();
        process.exit(0);
    });
    
    process.on('SIGINT', async () => {
        console.log('Received SIGINT, shutting down gracefully...');
        await server.stop();
        process.exit(0);
    });
    
    // Start server
    server.start().catch((error) => {
        console.error('Failed to start mock server:', error);
        process.exit(1);
    });
}

module.exports = MockOllamaServer;