# FFmpeg Builder

A professional-grade automated stream processing tool that handles SRT to HLS and HLS to MP4 conversions with a responsive web interface and real-time monitoring.

![FFmpeg Builder](https://img.shields.io/badge/FFmpeg-Builder-blue?style=for-the-badge&logo=ffmpeg)
![Node.js](https://img.shields.io/badge/Node.js-18+-green?style=for-the-badge&logo=node.js)
![WebSocket](https://img.shields.io/badge/WebSocket-Real--time-orange?style=for-the-badge)

## 🚀 Features

### Core Functionality

-   **SRT to HLS Conversion**: High-quality real-time streaming conversion with customizable parameters
-   **HLS to MP4 Conversion**: Efficient VOD conversion with optimized settings
-   **Real-time Monitoring**: WebSocket-based live progress updates and logging
-   **Process Management**: Start, stop, and monitor multiple concurrent conversions
-   **Command Preview**: Preview FFmpeg commands before execution

### Technical Features

-   **Responsive Design**: Mobile-friendly interface that works on all devices
-   **Input Validation**: Comprehensive client and server-side validation
-   **Error Handling**: Robust error handling and recovery mechanisms
-   **Security**: Rate limiting, input sanitization, and security headers
-   **Logging**: Comprehensive logging with rotation and monitoring
-   **Process Control**: Graceful shutdown and process management

## 📋 Requirements

### System Requirements

-   **OS**: Ubuntu 20.04+ / Amazon Linux 2
-   **CPU**: 2+ cores recommended
-   **RAM**: 4GB+ recommended
-   **Storage**: 20GB+ for application and output files
-   **Network**: Stable internet connection for SRT streams

### Software Dependencies

-   **Node.js**: 18.0 or higher
-   **FFmpeg**: 4.4 or higher with SRT support
-   **PM2**: For production process management
-   **Nginx**: For reverse proxy (production)

## 🛠 Installation

### Quick Start (Local Development)

```bash
# Clone the repository
git clone <repository-url>
cd ffmpeg-builder

# Install dependencies
npm install

# Copy environment configuration
cp env.example .env

# Start development server
npm run dev

# Open browser
open http://localhost:3000
```

### Production Deployment on AWS EC2

1. **Launch EC2 Instance**

    - Instance Type: t3.medium or higher
    - OS: Ubuntu 20.04 LTS
    - Security Group: Allow HTTP (80), HTTPS (443), SSH (22)
    - Storage: At least 20GB EBS volume

2. **Run Installation Script**

    ```bash
    # Upload your code to the server
    scp -r . ubuntu@your-ec2-ip:/tmp/ffmpeg-builder-repo/

    # SSH into your instance
    ssh ubuntu@your-ec2-ip

    # Make installation script executable
    chmod +x /tmp/ffmpeg-builder-repo/deploy/install.sh

    # Run installation
    sudo /tmp/ffmpeg-builder-repo/deploy/install.sh
    ```

3. **Access Application**
    - Open `http://your-ec2-public-ip` in your browser
    - The application should be running and accessible

## 🏗 Architecture

### System Components

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Web Browser   │◄──►│   Nginx Proxy    │◄──►│  Node.js Server │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                                         │
                       ┌──────────────────┐             │
                       │   WebSocket      │◄────────────┤
                       │   Connection     │             │
                       └──────────────────┘             │
                                                         │
                       ┌──────────────────┐             │
                       │   FFmpeg         │◄────────────┤
                       │   Processes      │             │
                       └──────────────────┘             │
                                                         │
                       ┌──────────────────┐             │
                       │   File System    │◄────────────┘
                       │   (/var/output)  │
                       └──────────────────┘
```

### API Endpoints

#### Health Check

```http
GET /api/health
```

Response:

```json
{
	"status": "healthy",
	"timestamp": "2024-01-01T00:00:00.000Z"
}
```

#### SRT to HLS Conversion

```http
POST /api/convert/srt-to-hls
Content-Type: application/json

{
  "srtAddress": "192.168.1.100",
  "srtPort": 8888,
  "streamId": "optional_stream_id",
  "passphrase": "optional_passphrase",
  "outputPath": "streams/live",
  "hlsName": "stream"
}
```

Response:

```json
{
	"message": "SRT to HLS conversion started",
	"processId": "uuid-string",
	"timestamp": "2024-01-01T00:00:00.000Z"
}
```

#### HLS to MP4 Conversion

```http
POST /api/convert/hls-to-mp4
Content-Type: application/json

{
  "hlsInputUrl": "https://example.com/stream.m3u8",
  "outputPath": "recordings",
  "mp4Name": "recording"
}
```

#### Process Management

```http
GET /api/processes
POST /api/stop/{processId}
```

### WebSocket Events

The application uses WebSocket for real-time updates:

```javascript
// Connection
ws://localhost:3000

// Message Types
{
  "type": "progress",
  "processId": "uuid",
  "data": "FFmpeg output...",
  "timestamp": "2024-01-01T00:00:00.000Z"
}

{
  "type": "completed",
  "processId": "uuid",
  "message": "Conversion completed successfully",
  "timestamp": "2024-01-01T00:00:00.000Z"
}

{
  "type": "error",
  "processId": "uuid",
  "message": "Conversion failed",
  "error": "Error details...",
  "timestamp": "2024-01-01T00:00:00.000Z"
}
```

## ⚙️ Configuration

### Environment Variables

| Variable                   | Default         | Description                |
| -------------------------- | --------------- | -------------------------- |
| `PORT`                     | 3000            | Server port                |
| `NODE_ENV`                 | development     | Environment mode           |
| `OUTPUT_PATH`              | ./output        | Output directory path      |
| `LOG_LEVEL`                | info            | Logging level              |
| `FFMPEG_PATH`              | /usr/bin/ffmpeg | FFmpeg binary path         |
| `MAX_CONCURRENT_PROCESSES` | 3               | Max concurrent conversions |

### FFmpeg Command Templates

#### SRT to HLS Template

```bash
ffmpeg -nostdin \
-fflags +genpts+discardcorrupt+igndts+flush_packets \
-err_detect ignore_err -rw_timeout 15000000 \
-analyzeduration 10M -probesize 50M \
-i "srt://HOST:PORT?mode=caller&..." \
-map 0:v:0 -map 0:a:0 \
-c:v libx264 -preset slow -crf 23 -r 50 -g 300 \
-keyint_min 300 -sc_threshold 0 \
-c:a aac -ac 2 -b:a 128k \
-f hls -hls_time 6 -hls_list_size 0 \
-hls_flags independent_segments \
-hls_segment_filename "segments_%03d.ts" \
-y "output.m3u8"
```

#### HLS to MP4 Template

```bash
ffmpeg \
-fflags +genpts+discardcorrupt \
-reconnect 1 -reconnect_streamed 1 \
-reconnect_delay_max 2 \
-i "HLS_URL" \
-map 0:v:0 -map 0:a:0 \
-c:v copy -c:a aac -b:a 128k \
-profile:a aac_low -bsf:a aac_adtstoasc \
-movflags +faststart+frag_keyframe+empty_moov \
-y "output.mp4"
```

## 📊 Monitoring & Maintenance

### Production Monitoring

The application includes comprehensive monitoring:

1. **Health Checks**: Automatic health monitoring every 5 minutes
2. **Disk Space**: Automatic cleanup of files older than 7 days
3. **Memory Usage**: Memory usage alerts and monitoring
4. **Process Monitoring**: Automatic restart of failed processes

### Useful Commands

```bash
# Check application status
sudo -u ffmpeg-builder pm2 status

# View logs
sudo -u ffmpeg-builder pm2 logs ffmpeg-builder

# Restart application
sudo -u ffmpeg-builder pm2 restart ffmpeg-builder

# Monitor resources
sudo -u ffmpeg-builder pm2 monit

# Check output files
ls -la /var/ffmpeg-output/

# Check system resources
htop
df -h
```

### Log Files

-   **Application Logs**: `/var/log/ffmpeg-builder/`
-   **Nginx Logs**: `/var/log/nginx/`
-   **System Logs**: `/var/log/syslog`

## 🔧 Troubleshooting

### Common Issues

#### 1. FFmpeg Not Found

```bash
# Check FFmpeg installation
which ffmpeg
ffmpeg -version

# Install FFmpeg if missing
sudo apt-get update
sudo apt-get install ffmpeg
```

#### 2. Permission Issues

```bash
# Fix ownership
sudo chown -R ffmpeg-builder:ffmpeg-builder /opt/ffmpeg-builder
sudo chown -R ffmpeg-builder:ffmpeg-builder /var/ffmpeg-output
```

#### 3. Port Already in Use

```bash
# Check what's using port 3000
sudo netstat -tulpn | grep :3000

# Kill process if needed
sudo kill -9 <PID>
```

#### 4. WebSocket Connection Issues

-   Check firewall settings
-   Verify Nginx configuration
-   Check browser console for errors

#### 5. SRT Connection Issues

-   Verify SRT source is accessible
-   Check firewall rules on both ends
-   Validate SRT parameters (passphrase, stream ID)

### Debug Mode

Enable debug logging:

```bash
# Set environment variable
export LOG_LEVEL=debug

# Restart application
sudo -u ffmpeg-builder pm2 restart ffmpeg-builder
```

## 🚦 Testing

### Manual Testing

1. **SRT to HLS**:

    - Set up SRT source (OBS, ffmpeg, etc.)
    - Configure SRT parameters in the web interface
    - Start conversion and monitor progress
    - Verify HLS output files

2. **HLS to MP4**:
    - Use a publicly available HLS stream
    - Configure output parameters
    - Start conversion and monitor progress
    - Verify MP4 output file

### Load Testing

For production environments, test with multiple concurrent streams:

```bash
# Example load test script
for i in {1..5}; do
  curl -X POST http://localhost:3000/api/convert/hls-to-mp4 \
  -H "Content-Type: application/json" \
  -d "{\"hlsInputUrl\":\"https://example.com/stream$i.m3u8\",\"outputPath\":\"test\",\"mp4Name\":\"test$i\"}" &
done
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests if applicable
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🆘 Support

For support and questions:

-   Check the troubleshooting section above
-   Review the logs for error details
-   Check FFmpeg documentation for command-specific issues
-   Ensure all system requirements are met

## 🏷 Version History

-   **v1.0.0**: Initial release with SRT to HLS and HLS to MP4 conversion
-   Full WebSocket support and real-time monitoring
-   Production-ready deployment scripts
-   Comprehensive error handling and logging

---

Built with ❤️ for the video streaming community
