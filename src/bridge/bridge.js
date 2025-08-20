/**
 * Gemini-OpenAI Bridge
 * Minimal implementation to pass tests (TDD Green Phase)
 */

/**
 * Clean and transform Gemini-style request to OpenAI format
 * @param {Object} geminiRequest - The request from qwen-code
 * @returns {Object} - Clean OpenAI-compatible request
 */
function cleanRequest(geminiRequest) {
    // Handle null/undefined requests
    if (!geminiRequest) {
        return {
            model: 'qwen3-coder:latest'
        };
    }

    // Start with a clean request
    const cleaned = {
        model: geminiRequest.model || 'qwen3-coder:latest'
    };

    // Preserve messages
    if (geminiRequest.messages) {
        cleaned.messages = [...geminiRequest.messages];
    }

    // Handle systemInstruction - convert to system message
    if (geminiRequest.systemInstruction && geminiRequest.systemInstruction.parts) {
        const systemContent = geminiRequest.systemInstruction.parts
            .map(part => part.text || '')
            .join('\n');
        
        if (systemContent) {
            // Add system message at the beginning
            if (!cleaned.messages) {
                cleaned.messages = [];
            }
            cleaned.messages.unshift({
                role: 'system',
                content: systemContent
            });
        }
    }

    // Extract temperature from generationConfig or use direct value
    if (geminiRequest.temperature !== undefined) {
        cleaned.temperature = geminiRequest.temperature;
    } else if (geminiRequest.generationConfig && geminiRequest.generationConfig.temperature !== undefined) {
        cleaned.temperature = geminiRequest.generationConfig.temperature;
    }

    // Handle max_tokens with cap for excessive requests
    let maxTokens = geminiRequest.max_tokens;
    if (maxTokens === undefined && geminiRequest.generationConfig) {
        maxTokens = geminiRequest.generationConfig.maxOutputTokens;
    }
    
    if (maxTokens !== undefined) {
        // Cap excessive token requests (qwen-code often requests 200k+)
        cleaned.max_tokens = maxTokens > 100000 ? 4096 : maxTokens;
    }

    // Preserve other OpenAI-compatible fields
    const openaiFields = ['top_p', 'frequency_penalty', 'presence_penalty', 'stream', 'stop', 'n'];
    openaiFields.forEach(field => {
        if (geminiRequest[field] !== undefined) {
            cleaned[field] = geminiRequest[field];
        }
    });

    // NOTE: We intentionally DO NOT copy these Gemini-specific fields:
    // - generationConfig (extracted what we need)
    // - safetySettings (not compatible with OpenAI)
    // - tools (different format)
    // - toolConfig (not compatible)
    // - systemInstruction (converted to message)

    return cleaned;
}

/**
 * Create Express app for the bridge
 * @returns {Object} - Express app instance
 */
function createApp() {
    const express = require('express');
    const app = express();
    
    app.use(express.json({ limit: '50mb' }));
    
    const TARGET_URL = process.env.BRIDGE_TARGET_URL || process.env.OPENAI_BASE_URL;
    
    // Health check endpoint
    app.get('/health', (req, res) => {
        res.json({
            status: 'healthy',
            bridge: 'gemini-openai-bridge',
            target: TARGET_URL,
            uptime: process.uptime()
        });
    });
    
    // Models endpoint - forward as-is
    app.get('/v1/models', async (req, res) => {
        try {
            const response = await fetch(TARGET_URL + '/models', {
                headers: {
                    'Authorization': req.headers.authorization || ''
                }
            });
            
            const data = await response.json();
            res.json(data);
        } catch (error) {
            res.status(500).json({ error: 'Failed to fetch models' });
        }
    });
    
    // Chat completions endpoint - main bridge functionality
    app.post('/v1/chat/completions', async (req, res) => {
        try {
            const DEBUG = process.env.BRIDGE_DEBUG === 'true';
            
            console.log(`[${new Date().toISOString()}] Incoming request to bridge`);
            
            if (DEBUG) {
                console.log('=== INCOMING REQUEST ===');
                console.log('Headers:', req.headers);
                console.log('Body:', JSON.stringify(req.body, null, 2));
                console.log('Messages:', req.body.messages ? req.body.messages.map(m => ({role: m.role, content: m.content?.substring(0, 100) + '...'})) : 'none');
            }
            
            // Clean the request using our tested function
            const cleanedRequest = cleanRequest(req.body);
            
            if (DEBUG) {
                console.log('=== CLEANED REQUEST ===');
                console.log(JSON.stringify(cleanedRequest, null, 2));
            }
            
            const targetUrl = TARGET_URL + '/chat/completions';
            console.log(`Forwarding to: ${targetUrl}`);
            
            // Forward to target server
            const response = await fetch(targetUrl, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                    'Authorization': req.headers.authorization || '',
                    'Accept': req.headers.accept || 'application/json',
                },
                body: JSON.stringify(cleanedRequest)
            });
            
            if (DEBUG) {
                console.log('=== TARGET RESPONSE ===');
                console.log('Status:', response.status);
                console.log('Headers:', Object.fromEntries(response.headers.entries()));
                console.log('Stream flag:', cleanedRequest.stream);
                console.log('Content-Type:', response.headers.get('content-type'));
            }
            
            // Handle streaming responses
            if (cleanedRequest.stream === true) {
                // Copy headers from target response
                res.status(response.status);
                response.headers.forEach((value, key) => {
                    res.setHeader(key, value);
                });
                
                // Stream the response body
                if (response.body) {
                    const reader = response.body.getReader();
                    const decoder = new TextDecoder();
                    
                    try {
                        while (true) {
                            const { done, value } = await reader.read();
                            if (done) break;
                            
                            const chunk = decoder.decode(value, { stream: true });
                            res.write(chunk);
                        }
                        res.end();
                    } catch (error) {
                        res.status(500).json({
                            error: {
                                message: 'Stream error: ' + error.message,
                                type: 'stream_error'
                            }
                        });
                    }
                } else {
                    res.end();
                }
            } else {
                // Handle non-streaming responses as before
                const data = await response.json();
                res.status(response.status).json(data);
            }
            
        } catch (error) {
            const DEBUG = process.env.BRIDGE_DEBUG === 'true';
            
            if (DEBUG) {
                console.log('=== BRIDGE ERROR ===');
                console.log('Error:', error.message);
                console.log('Stack:', error.stack);
            }
            
            res.status(500).json({
                error: {
                    message: 'Bridge error: ' + error.message,
                    type: 'bridge_error'
                }
            });
        }
    });
    
    return app;
}

/**
 * Start the bridge server
 */
function startServer() {
    console.log('[BRIDGE] Starting bridge server initialization...');
    console.log('[BRIDGE] Current working directory:', process.cwd());
    console.log('[BRIDGE] Node version:', process.version);
    
    // Log ALL environment variables for debugging
    console.log('[BRIDGE] Environment variables:');
    Object.keys(process.env).forEach(key => {
        if (key.includes('BRIDGE') || key.includes('OPENAI') || key.includes('GEMINI')) {
            console.log(`[BRIDGE]   ${key}=${process.env[key]}`);
        }
    });
    
    const PORT = process.env.BRIDGE_PORT || 8080;
    const TARGET_URL = process.env.BRIDGE_TARGET_URL || process.env.OPENAI_BASE_URL;
    const DEBUG = process.env.BRIDGE_DEBUG === 'true';
    
    if (!TARGET_URL) {
        console.error('[BRIDGE] ERROR: No TARGET_URL or OPENAI_BASE_URL defined!');
        console.error('[BRIDGE] Cannot start bridge without a target URL');
        process.exit(1);
    }
    
    console.log('===========================================');
    console.log('Gemini-OpenAI Bridge Starting...');
    console.log(`Bridge Port: ${PORT}`);
    console.log(`Target URL: ${TARGET_URL}`);
    console.log(`Debug Mode: ${DEBUG ? 'ON' : 'OFF'}`);
    console.log('===========================================');
    
    try {
        const app = createApp();
        
        const server = app.listen(PORT, '0.0.0.0', () => {
            console.log(`\n✅ Gemini-OpenAI Bridge running on port ${PORT}`);
            console.log(`📡 Forwarding to: ${TARGET_URL}`);
            console.log('\nWaiting for requests...\n');
            console.log('[BRIDGE] Server successfully started and listening');
        });
        
        server.on('error', (err) => {
            console.error('[BRIDGE] Server error:', err);
            if (err.code === 'EADDRINUSE') {
                console.error(`[BRIDGE] Port ${PORT} is already in use!`);
            }
            process.exit(1);
        });
        
        // Handle shutdown gracefully
        process.on('SIGTERM', () => {
            console.log('\n[BRIDGE] Received SIGTERM, shutting down bridge...');
            server.close(() => {
                console.log('[BRIDGE] Server closed');
                process.exit(0);
            });
        });
        
        process.on('uncaughtException', (err) => {
            console.error('[BRIDGE] Uncaught exception:', err);
            process.exit(1);
        });
        
        return server;
    } catch (error) {
        console.error('[BRIDGE] Failed to start server:', error);
        process.exit(1);
    }
}

// Export for testing
module.exports = {
    cleanRequest,
    createApp,
    startServer
};

// If this file is run directly, start the server
if (require.main === module) {
    startServer();
}