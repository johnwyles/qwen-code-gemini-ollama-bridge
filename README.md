# Qwen Code Docker

A production-ready Docker environment for Qwen Code CLI with optional Gemini-OpenAI bridge for API routing.

## 📚 Documentation

- [Configuration Guide](docs/CONFIGURATION.md) - Detailed setup and configuration options
- [Troubleshooting Guide](docs/TROUBLESHOOTING.md) - Common issues and solutions
- [API Configuration](.env.example) - Environment variable template

## Features

- 🐳 **Dockerized Environment** - Isolated, reproducible development environment
- 🌉 **[Gemini-OpenAI Bridge](src/bridge/)** - Route API requests through a configurable bridge
- 🔧 **Auto-rebuild Detection** - Automatically detects when rebuild is needed
- 👤 **User Management** - Runs as non-root user with sudo access
- 🔍 **[Comprehensive Diagnostics](scripts/utils/diagnose.sh)** - Built-in diagnostic tools for troubleshooting
- 📦 **Clean Project Structure** - Organized following Docker best practices

## Quick Start

1. **Clone the repository**
   ```bash
   git clone https://github.com/yourusername/qwen-code-docker.git
   cd qwen-code-docker
   ```

2. **Configure environment**
   ```bash
   cp config/.env.example .env
   # Edit .env with your API settings
   ```
   See [Configuration Guide](docs/CONFIGURATION.md) for detailed setup instructions.

3. **Start the container**
   ```bash
   ./scripts/start.sh
   ```

## Project Structure

```
qwen-code-docker/
├── docker/                 # Docker configuration
│   ├── Dockerfile         
│   └── docker-compose.yml
├── scripts/               # Executable scripts
│   ├── entrypoint/       # Container lifecycle
│   ├── bridge/           # Bridge utilities
│   ├── utils/            # Diagnostic tools
│   └── start.sh          # Main entry point
├── src/                   # Source code
│   └── bridge/           # Bridge application
├── config/                # Configuration
│   └── .env.example      # Environment template
├── docs/                  # Documentation
├── home/                  # User home mount
└── tests/                 # Test files
```

## Configuration

Copy [`config/.env.example`](config/.env.example) to `.env` and configure:

```bash
# API Configuration
OPENAI_BASE_URL=http://localhost:11434/v1
OPENAI_API_KEY=your-api-key-here
OPENAI_MODEL=qwen3-coder:latest

# Bridge Configuration (optional)
USE_GEMINI_BRIDGE=true
BRIDGE_TARGET_URL=http://your-server:port/v1
BRIDGE_PORT=8080
```

### Using with Open Web UI

If you're using Open Web UI as your interface to Ollama, you'll need an API key for external applications like this container. Open Web UI acts as a gateway that provides authentication and access control to your local Ollama models.

**To get your API key from Open Web UI:**

1. Open your Open Web UI interface (usually `http://localhost:3000`)
2. Go to **Settings** → **Account** → **API Keys**
3. Click **Create new API key**
4. Copy the generated key

**Configure your `.env` file:**

```bash
# For Open Web UI (replace with your actual Open Web UI URL and API key)
OPENAI_BASE_URL=http://localhost:3000/ollama/v1
OPENAI_API_KEY=owui_xxxxxxxxxxxxxxxxxxxxxxxxxxxx
OPENAI_MODEL=qwen2.5-coder:latest
```

📖 **[Full Configuration Documentation](docs/CONFIGURATION.md)**

## Usage

### Starting the Container

```bash
./scripts/start.sh
```

The [`start.sh`](scripts/start.sh) script will:
- Check if configuration exists (run setup if needed)
- Detect if rebuild is required
- Start or attach to existing container
- Launch Qwen CLI with proper environment

### Diagnostics

Run comprehensive diagnostics:
```bash
./scripts/utils/diagnose.sh
```

The [`diagnose.sh`](scripts/utils/diagnose.sh) script checks:
- Docker status
- Image and container health
- User configuration
- Bridge functionality
- Environment variables

### Bridge Mode

When `USE_GEMINI_BRIDGE=true`, the [bridge](src/bridge/):
1. Listens on `localhost:8080`
2. Forwards requests to `BRIDGE_TARGET_URL`
3. Handles authentication headers
4. Supports streaming responses

See [Bridge Documentation](src/bridge/README.md) for implementation details.

## Development

### Building the Image

```bash
cd docker
docker compose build
```

### Running Tests

```bash
cd tests
./run-tests.sh
```

## Troubleshooting

### Common Issues

1. **Connection Error**: Check API key and endpoint in `.env`
2. **Permission Denied**: The container fixes permissions automatically
3. **Bridge Not Working**: Run [`./scripts/utils/diagnose.sh`](scripts/utils/diagnose.sh) for details

### Getting Help

- Run diagnostics: [`./scripts/utils/diagnose.sh`](scripts/utils/diagnose.sh)
- Check logs: `docker logs qwen-code`
- Bridge logs: `docker exec qwen-code cat /workspace/logs/bridge.log`
- 📖 **[Full Troubleshooting Guide](docs/TROUBLESHOOTING.md)**

## Architecture

The system consists of:

1. **Qwen CLI Container**: Main environment with qwen-code installed ([Dockerfile](docker/Dockerfile))
2. **[Gemini-OpenAI Bridge](src/bridge/)**: Optional Node.js proxy for API routing
3. **Volume Mounts**: Persistent storage for workspace and configurations
4. **Health Monitoring**: Docker health checks and [diagnostic tools](scripts/utils/)

## License

MIT License - See LICENSE file for details

## Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request