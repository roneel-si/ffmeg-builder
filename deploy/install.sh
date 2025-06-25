#!/bin/bash

# FFmpeg Builder Installation Script for EC2
# This script installs all dependencies and sets up the application

set -e

echo "🚀 Starting FFmpeg Builder Installation..."

# Update system packages
echo "📦 Updating system packages..."
sudo apt-get update -y
sudo apt-get upgrade -y

# Install Node.js 18.x
echo "📦 Installing Node.js..."
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install FFmpeg
echo "📦 Installing FFmpeg..."
sudo apt-get install -y ffmpeg

# Install PM2 for process management
echo "📦 Installing PM2..."
sudo npm install -g pm2

# Install system dependencies
echo "📦 Installing system dependencies..."
sudo apt-get install -y \
    build-essential \
    curl \
    git \
    nginx \
    ufw \
    htop \
    unzip

# Create application user
echo "👤 Creating application user..."
sudo useradd -m -s /bin/bash ffmpeg-builder || true
sudo usermod -aG sudo ffmpeg-builder || true

# Create application directories
echo "📁 Creating application directories..."
sudo mkdir -p /opt/ffmpeg-builder
sudo mkdir -p /var/ffmpeg-output
sudo mkdir -p /var/log/ffmpeg-builder

# Set permissions
sudo chown -R ffmpeg-builder:ffmpeg-builder /opt/ffmpeg-builder
sudo chown -R ffmpeg-builder:ffmpeg-builder /var/ffmpeg-output
sudo chown -R ffmpeg-builder:ffmpeg-builder /var/log/ffmpeg-builder

# Clone or copy application files
echo "📥 Setting up application files..."
cd /opt/ffmpeg-builder

# If running from a Git repository
if [ -d "/tmp/ffmpeg-builder-repo" ]; then
    sudo cp -r /tmp/ffmpeg-builder-repo/* .
    sudo chown -R ffmpeg-builder:ffmpeg-builder .
fi

# Install Node.js dependencies
echo "📦 Installing Node.js dependencies..."
sudo -u ffmpeg-builder npm install --production

# Create environment file
echo "⚙️ Creating environment configuration..."
sudo -u ffmpeg-builder cp env.example .env
sudo -u ffmpeg-builder sed -i 's|OUTPUT_PATH=.*|OUTPUT_PATH=/var/ffmpeg-output|' .env
sudo -u ffmpeg-builder sed -i 's|LOG_FILE_PATH=.*|LOG_FILE_PATH=/var/log/ffmpeg-builder|' .env

# Configure Nginx
echo "🌐 Configuring Nginx..."
sudo tee /etc/nginx/sites-available/ffmpeg-builder > /dev/null <<EOF
server {
    listen 80;
    server_name _;

    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";

    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone \$binary_remote_addr zone=upload:10m rate=2r/s;

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 86400;
    }

    location /api/ {
        limit_req zone=api burst=20 nodelay;
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_cache_bypass \$http_upgrade;
        proxy_read_timeout 86400;
    }

    # Static file serving with caching
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg)$ {
        proxy_pass http://localhost:3000;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

# Enable Nginx site
sudo ln -sf /etc/nginx/sites-available/ffmpeg-builder /etc/nginx/sites-enabled/
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl restart nginx
sudo systemctl enable nginx

# Configure firewall
echo "🔥 Configuring firewall..."
sudo ufw allow ssh
sudo ufw allow 'Nginx Full'
echo "y" | sudo ufw enable

# Create PM2 ecosystem file
echo "⚙️ Creating PM2 configuration..."
sudo -u ffmpeg-builder tee /opt/ffmpeg-builder/ecosystem.config.js > /dev/null <<EOF
module.exports = {
  apps: [{
    name: 'ffmpeg-builder',
    script: 'server.js',
    instances: 1,
    exec_mode: 'cluster',
    env: {
      NODE_ENV: 'production',
      PORT: 3000
    },
    error_file: '/var/log/ffmpeg-builder/error.log',
    out_file: '/var/log/ffmpeg-builder/out.log',
    log_file: '/var/log/ffmpeg-builder/combined.log',
    time: true,
    max_restarts: 10,
    min_uptime: '10s',
    max_memory_restart: '1G',
    watch: false,
    ignore_watch: ['node_modules', 'logs', 'output'],
    env_production: {
      NODE_ENV: 'production',
      PORT: 3000
    }
  }]
};
EOF

# Start application with PM2
echo "🚀 Starting application..."
cd /opt/ffmpeg-builder
sudo -u ffmpeg-builder pm2 start ecosystem.config.js --env production
sudo -u ffmpeg-builder pm2 save
sudo pm2 startup systemd -u ffmpeg-builder --hp /home/ffmpeg-builder

# Setup log rotation
echo "📋 Setting up log rotation..."
sudo tee /etc/logrotate.d/ffmpeg-builder > /dev/null <<EOF
/var/log/ffmpeg-builder/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 0644 ffmpeg-builder ffmpeg-builder
    postrotate
        pm2 reloadLogs
    endscript
}
EOF

# Create monitoring script
echo "📊 Creating monitoring script..."
sudo tee /opt/ffmpeg-builder/monitor.sh > /dev/null <<'EOF'
#!/bin/bash

# FFmpeg Builder Monitoring Script

LOG_FILE="/var/log/ffmpeg-builder/monitor.log"
DATE=$(date '+%Y-%m-%d %H:%M:%S')

# Check if application is running
if ! pm2 describe ffmpeg-builder > /dev/null 2>&1; then
    echo "[$DATE] ERROR: FFmpeg Builder is not running" >> $LOG_FILE
    pm2 start ecosystem.config.js --env production
    echo "[$DATE] INFO: Attempted to restart FFmpeg Builder" >> $LOG_FILE
fi

# Check disk space
DISK_USAGE=$(df /var/ffmpeg-output | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 85 ]; then
    echo "[$DATE] WARNING: Disk usage is ${DISK_USAGE}%" >> $LOG_FILE
    # Clean up old files (older than 7 days)
    find /var/ffmpeg-output -type f -mtime +7 -delete
    echo "[$DATE] INFO: Cleaned up old output files" >> $LOG_FILE
fi

# Check memory usage
MEMORY_USAGE=$(free | awk 'FNR==2{printf "%.0f", $3/($3+$4)*100}')
if [ "$MEMORY_USAGE" -gt 85 ]; then
    echo "[$DATE] WARNING: Memory usage is ${MEMORY_USAGE}%" >> $LOG_FILE
fi

# Check FFmpeg availability
if ! command -v ffmpeg > /dev/null 2>&1; then
    echo "[$DATE] ERROR: FFmpeg is not available" >> $LOG_FILE
fi

echo "[$DATE] INFO: Health check completed" >> $LOG_FILE
EOF

sudo chmod +x /opt/ffmpeg-builder/monitor.sh
sudo chown ffmpeg-builder:ffmpeg-builder /opt/ffmpeg-builder/monitor.sh

# Setup cron job for monitoring
echo "⏰ Setting up monitoring cron job..."
(crontab -u ffmpeg-builder -l 2>/dev/null; echo "*/5 * * * * /opt/ffmpeg-builder/monitor.sh") | sudo -u ffmpeg-builder crontab -

# Final status check
echo "✅ Installation completed!"
echo ""
echo "🔍 Status Check:"
echo "- Node.js version: $(node --version)"
echo "- NPM version: $(npm --version)"
echo "- FFmpeg version: $(ffmpeg -version | head -n1)"
echo "- PM2 status:"
sudo -u ffmpeg-builder pm2 status
echo ""
echo "🌐 Application should be accessible at:"
echo "- Local: http://localhost"
echo "- External: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo 'YOUR_EC2_PUBLIC_IP')"
echo ""
echo "📋 Useful commands:"
echo "- Check logs: sudo -u ffmpeg-builder pm2 logs ffmpeg-builder"
echo "- Restart app: sudo -u ffmpeg-builder pm2 restart ffmpeg-builder"
echo "- Monitor: sudo -u ffmpeg-builder pm2 monit"
echo "- Check output: ls -la /var/ffmpeg-output/"
echo ""
echo "🎉 FFmpeg Builder is ready to use!" 