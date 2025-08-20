#!/usr/bin/env node

/**
 * Qwen Coder Docker - Connection Test Script
 * 
 * This script validates the configuration and tests the connection to the Ollama endpoint.
 * It checks environment variables, network connectivity, authentication, and model availability.
 * 
 * Usage:
 *   node tests/test-connection.js
 *   npm test (if configured in package.json)
 * 
 * Exit codes:
 *   0 - All tests passed
 *   1 - Configuration or connection errors
 *   2 - Authentication errors
 *   3 - Model availability errors
 */

const fs = require('fs');
const path = require('path');
const https = require('https');
const http = require('http');
const { URL } = require('url');

// ANSI color codes for output formatting
const colors = {
    reset: '\x1b[0m',
    bright: '\x1b[1m',
    red: '\x1b[31m',
    green: '\x1b[32m',
    yellow: '\x1b[33m',
    blue: '\x1b[34m',
    magenta: '\x1b[35m',
    cyan: '\x1b[36m'
};

// Test result tracking
let testResults = {
    passed: 0,
    failed: 0,
    warnings: 0,
    tests: []
};

/**
 * Print colored output to console
 */
function print(message, color = 'reset') {
    console.log(`${colors[color]}${message}${colors.reset}`);
}

/**
 * Record test result
 */
function recordTest(name, passed, message = '', isWarning = false) {
    const result = { name, passed, message, isWarning };
    testResults.tests.push(result);
    
    if (isWarning) {
        testResults.warnings++;
        print(`⚠ ${name}: ${message}`, 'yellow');
    } else if (passed) {
        testResults.passed++;
        print(`✓ ${name}`, 'green');
    } else {
        testResults.failed++;
        print(`✗ ${name}: ${message}`, 'red');
    }
}

/**
 * Load environment variables from .env file if it exists
 */
function loadEnvironment() {
    const envPath = path.join(process.cwd(), '.env');
    
    if (fs.existsSync(envPath)) {
        try {
            const envContent = fs.readFileSync(envPath, 'utf8');
            const lines = envContent.split('\n');
            
            for (const line of lines) {
                const trimmed = line.trim();
                if (trimmed && !trimmed.startsWith('#')) {
                    const [key, ...valueParts] = trimmed.split('=');
                    if (key && valueParts.length > 0) {
                        const value = valueParts.join('=').replace(/^["']|["']$/g, '');
                        process.env[key.trim()] = value;
                    }
                }
            }
            recordTest('Environment file loading', true);
        } catch (error) {
            recordTest('Environment file loading', false, `Failed to parse .env file: ${error.message}`);
            return false;
        }
    } else {
        recordTest('Environment file detection', true, 'No .env file found, using system environment variables', true);
    }
    
    return true;
}

/**
 * Validate required environment variables
 */
function validateEnvironment() {
    const required = ['OLLAMA_HOST'];
    const optional = {
        'OLLAMA_PROTOCOL': 'https',
        'OLLAMA_API_KEY': '',
        'MODEL_NAME': 'qwen2.5-coder',
        'OLLAMA_TIMEOUT': '30000'
    };
    
    let allValid = true;
    
    // Check required variables
    for (const key of required) {
        if (!process.env[key]) {
            recordTest(`Required variable ${key}`, false, 'Missing required environment variable');
            allValid = false;
        } else {
            recordTest(`Required variable ${key}`, true);
        }
    }
    
    // Set defaults for optional variables
    for (const [key, defaultValue] of Object.entries(optional)) {
        if (!process.env[key]) {
            process.env[key] = defaultValue;
            if (key === 'OLLAMA_API_KEY' && !defaultValue) {
                recordTest(`Optional variable ${key}`, true, 'No API key set (OK for local instances)', true);
            }
        } else {
            recordTest(`Optional variable ${key}`, true);
        }
    }
    
    return allValid;
}

/**
 * Test network connectivity to the Ollama endpoint
 */
function testConnectivity() {
    return new Promise((resolve) => {
        const host = process.env.OLLAMA_HOST;
        const protocol = process.env.OLLAMA_PROTOCOL || 'https';
        const timeout = parseInt(process.env.OLLAMA_TIMEOUT) || 30000;
        
        try {
            const url = new URL(`${protocol}://${host}`);
            const client = protocol === 'https' ? https : http;
            
            const options = {
                hostname: url.hostname,
                port: url.port || (protocol === 'https' ? 443 : 80),
                path: '/api/version',
                method: 'GET',
                timeout: timeout,
                // Allow self-signed certificates for development
                rejectUnauthorized: false
            };
            
            const req = client.request(options, (res) => {
                recordTest('Network connectivity', true);
                resolve(true);
            });
            
            req.on('error', (error) => {
                recordTest('Network connectivity', false, `Connection failed: ${error.message}`);
                resolve(false);
            });
            
            req.on('timeout', () => {
                recordTest('Network connectivity', false, `Connection timeout after ${timeout}ms`);
                req.destroy();
                resolve(false);
            });
            
            req.end();
            
        } catch (error) {
            recordTest('Network connectivity', false, `Invalid endpoint configuration: ${error.message}`);
            resolve(false);
        }
    });
}

/**
 * Test API authentication
 */
function testAuthentication() {
    return new Promise((resolve) => {
        const host = process.env.OLLAMA_HOST;
        const protocol = process.env.OLLAMA_PROTOCOL || 'https';
        const apiKey = process.env.OLLAMA_API_KEY;
        const timeout = parseInt(process.env.OLLAMA_TIMEOUT) || 30000;
        
        try {
            const url = new URL(`${protocol}://${host}`);
            const client = protocol === 'https' ? https : http;
            
            const options = {
                hostname: url.hostname,
                port: url.port || (protocol === 'https' ? 443 : 80),
                path: '/api/tags',
                method: 'GET',
                timeout: timeout,
                rejectUnauthorized: false,
                headers: {}
            };
            
            // Add authentication header if API key is provided
            if (apiKey && apiKey.trim()) {
                options.headers['Authorization'] = `Bearer ${apiKey}`;
            }
            
            const req = client.request(options, (res) => {
                if (res.statusCode === 200) {
                    recordTest('API authentication', true);
                    resolve(true);
                } else if (res.statusCode === 401) {
                    recordTest('API authentication', false, 'Invalid API key or authentication required');
                    resolve(false);
                } else if (res.statusCode === 403) {
                    recordTest('API authentication', false, 'Access forbidden - check API key permissions');
                    resolve(false);
                } else {
                    recordTest('API authentication', false, `HTTP ${res.statusCode}: ${res.statusMessage}`);
                    resolve(false);
                }
            });
            
            req.on('error', (error) => {
                recordTest('API authentication', false, `Request failed: ${error.message}`);
                resolve(false);
            });
            
            req.on('timeout', () => {
                recordTest('API authentication', false, `Request timeout after ${timeout}ms`);
                req.destroy();
                resolve(false);
            });
            
            req.end();
            
        } catch (error) {
            recordTest('API authentication', false, `Request setup failed: ${error.message}`);
            resolve(false);
        }
    });
}

/**
 * Test model availability
 */
function testModelAvailability() {
    return new Promise((resolve) => {
        const host = process.env.OLLAMA_HOST;
        const protocol = process.env.OLLAMA_PROTOCOL || 'https';
        const apiKey = process.env.OLLAMA_API_KEY;
        const modelName = process.env.MODEL_NAME || 'qwen2.5-coder';
        const timeout = parseInt(process.env.OLLAMA_TIMEOUT) || 30000;
        
        try {
            const url = new URL(`${protocol}://${host}`);
            const client = protocol === 'https' ? https : http;
            
            const options = {
                hostname: url.hostname,
                port: url.port || (protocol === 'https' ? 443 : 80),
                path: '/api/tags',
                method: 'GET',
                timeout: timeout,
                rejectUnauthorized: false,
                headers: {}
            };
            
            if (apiKey && apiKey.trim()) {
                options.headers['Authorization'] = `Bearer ${apiKey}`;
            }
            
            const req = client.request(options, (res) => {
                let data = '';
                
                res.on('data', (chunk) => {
                    data += chunk;
                });
                
                res.on('end', () => {
                    try {
                        const response = JSON.parse(data);
                        const models = response.models || [];
                        
                        const modelFound = models.some(model => 
                            model.name === modelName || 
                            model.name.startsWith(modelName + ':') ||
                            model.name === modelName + ':latest'
                        );
                        
                        if (modelFound) {
                            recordTest('Model availability', true, `Model "${modelName}" is available`);
                            resolve(true);
                        } else {
                            const availableModels = models.map(m => m.name).join(', ');
                            recordTest('Model availability', false, 
                                `Model "${modelName}" not found. Available models: ${availableModels || 'none'}`);
                            resolve(false);
                        }
                    } catch (parseError) {
                        recordTest('Model availability', false, `Failed to parse response: ${parseError.message}`);
                        resolve(false);
                    }
                });
            });
            
            req.on('error', (error) => {
                recordTest('Model availability', false, `Request failed: ${error.message}`);
                resolve(false);
            });
            
            req.on('timeout', () => {
                recordTest('Model availability', false, `Request timeout after ${timeout}ms`);
                req.destroy();
                resolve(false);
            });
            
            req.end();
            
        } catch (error) {
            recordTest('Model availability', false, `Request setup failed: ${error.message}`);
            resolve(false);
        }
    });
}

/**
 * Test basic model functionality with a simple request
 */
function testModelFunctionality() {
    return new Promise((resolve) => {
        const host = process.env.OLLAMA_HOST;
        const protocol = process.env.OLLAMA_PROTOCOL || 'https';
        const apiKey = process.env.OLLAMA_API_KEY;
        const modelName = process.env.MODEL_NAME || 'qwen2.5-coder';
        const timeout = parseInt(process.env.OLLAMA_TIMEOUT) || 30000;
        
        try {
            const url = new URL(`${protocol}://${host}`);
            const client = protocol === 'https' ? https : http;
            
            const requestData = JSON.stringify({
                model: modelName,
                prompt: 'Hello',
                stream: false,
                options: {
                    num_predict: 10,
                    temperature: 0.1
                }
            });
            
            const options = {
                hostname: url.hostname,
                port: url.port || (protocol === 'https' ? 443 : 80),
                path: '/api/generate',
                method: 'POST',
                timeout: timeout * 2, // Give more time for generation
                rejectUnauthorized: false,
                headers: {
                    'Content-Type': 'application/json',
                    'Content-Length': Buffer.byteLength(requestData)
                }
            };
            
            if (apiKey && apiKey.trim()) {
                options.headers['Authorization'] = `Bearer ${apiKey}`;
            }
            
            const req = client.request(options, (res) => {
                let data = '';
                
                res.on('data', (chunk) => {
                    data += chunk;
                });
                
                res.on('end', () => {
                    try {
                        const response = JSON.parse(data);
                        
                        if (res.statusCode === 200 && response.response) {
                            recordTest('Model functionality', true, 'Model responded successfully');
                            resolve(true);
                        } else if (response.error) {
                            recordTest('Model functionality', false, `Model error: ${response.error}`);
                            resolve(false);
                        } else {
                            recordTest('Model functionality', false, `Unexpected response: HTTP ${res.statusCode}`);
                            resolve(false);
                        }
                    } catch (parseError) {
                        recordTest('Model functionality', false, `Failed to parse response: ${parseError.message}`);
                        resolve(false);
                    }
                });
            });
            
            req.on('error', (error) => {
                recordTest('Model functionality', false, `Request failed: ${error.message}`);
                resolve(false);
            });
            
            req.on('timeout', () => {
                recordTest('Model functionality', false, `Request timeout after ${timeout * 2}ms`);
                req.destroy();
                resolve(false);
            });
            
            req.write(requestData);
            req.end();
            
        } catch (error) {
            recordTest('Model functionality', false, `Request setup failed: ${error.message}`);
            resolve(false);
        }
    });
}

/**
 * Display configuration summary
 */
function displayConfiguration() {
    print('\n' + '='.repeat(60), 'cyan');
    print('CONFIGURATION SUMMARY', 'cyan');
    print('='.repeat(60), 'cyan');
    
    const config = {
        'Ollama Host': process.env.OLLAMA_HOST || 'Not set',
        'Protocol': process.env.OLLAMA_PROTOCOL || 'https',
        'API Key': process.env.OLLAMA_API_KEY ? '[CONFIGURED]' : '[NOT SET]',
        'Model Name': process.env.MODEL_NAME || 'qwen2.5-coder',
        'Timeout': `${process.env.OLLAMA_TIMEOUT || 30000}ms`,
        'Environment File': fs.existsSync(path.join(process.cwd(), '.env')) ? 'Found' : 'Not found'
    };
    
    for (const [key, value] of Object.entries(config)) {
        print(`${key.padEnd(20)}: ${value}`, 'blue');
    }
    print('');
}

/**
 * Display test results summary
 */
function displayResults() {
    print('\n' + '='.repeat(60), 'cyan');
    print('TEST RESULTS SUMMARY', 'cyan');
    print('='.repeat(60), 'cyan');
    
    print(`Total Tests: ${testResults.tests.length}`, 'blue');
    print(`Passed: ${testResults.passed}`, 'green');
    print(`Failed: ${testResults.failed}`, testResults.failed > 0 ? 'red' : 'green');
    print(`Warnings: ${testResults.warnings}`, testResults.warnings > 0 ? 'yellow' : 'blue');
    
    if (testResults.failed === 0) {
        print('\n🎉 All tests passed! Your configuration is working correctly.', 'green');
        print('You can now run: docker-compose up -d', 'green');
    } else {
        print('\n❌ Some tests failed. Please check the errors above and fix your configuration.', 'red');
        print('\nTroubleshooting tips:', 'yellow');
        print('1. Verify your .env file settings', 'yellow');
        print('2. Check network connectivity to the endpoint', 'yellow');
        print('3. Validate your API key', 'yellow');
        print('4. Ensure the model is available', 'yellow');
    }
    
    print('\nFor detailed troubleshooting, see the README.md file.', 'blue');
}

/**
 * Main test execution
 */
async function runTests() {
    print('Qwen Coder Docker - Connection Test', 'bright');
    print('=' * 40, 'cyan');
    print('');
    
    // Load environment
    if (!loadEnvironment()) {
        process.exit(1);
    }
    
    // Display configuration
    displayConfiguration();
    
    // Validate environment variables
    if (!validateEnvironment()) {
        displayResults();
        process.exit(1);
    }
    
    // Run connectivity tests
    print('Running connectivity tests...', 'blue');
    print('');
    
    const connectivityPassed = await testConnectivity();
    if (!connectivityPassed) {
        displayResults();
        process.exit(1);
    }
    
    const authPassed = await testAuthentication();
    if (!authPassed) {
        displayResults();
        process.exit(2);
    }
    
    const modelAvailable = await testModelAvailability();
    if (!modelAvailable) {
        displayResults();
        process.exit(3);
    }
    
    // Optional: Test basic functionality (may take longer)
    const args = process.argv.slice(2);
    if (args.includes('--full') || args.includes('-f')) {
        print('\nRunning full functionality test...', 'blue');
        await testModelFunctionality();
    } else {
        recordTest('Model functionality', true, 'Skipped (use --full for complete test)', true);
    }
    
    // Display final results
    displayResults();
    
    // Exit with appropriate code
    process.exit(testResults.failed > 0 ? 1 : 0);
}

// Handle uncaught errors
process.on('uncaughtException', (error) => {
    print(`\nUncaught error: ${error.message}`, 'red');
    process.exit(1);
});

process.on('unhandledRejection', (reason, promise) => {
    print(`\nUnhandled rejection: ${reason}`, 'red');
    process.exit(1);
});

// Run the tests
if (require.main === module) {
    runTests();
}

module.exports = {
    runTests,
    testResults,
    loadEnvironment,
    validateEnvironment,
    testConnectivity,
    testAuthentication,
    testModelAvailability,
    testModelFunctionality
};