# EC2 Deployment Guide

This guide will help you deploy the FFmpeg Builder application to an AWS EC2 instance using the automated deployment script.

## Prerequisites

### 1. EC2 Instance Setup

-   Launch an Ubuntu 20.04+ EC2 instance
-   Instance type: t3.medium or higher recommended
-   Storage: At least 20GB EBS volume
-   Security Group: Allow SSH (port 22) and your application port (3333)

### 2. SSH Key Setup

-   Ensure you have your EC2 SSH key pair
-   Default expected location: `/.ssh/id_rsa`
-   Make sure the key has proper permissions: `chmod 600 /.ssh/id_rsa`

### 3. Local Requirements

-   `rsync` installed on your local machine
-   `ssh` client available
-   Internet connection for downloading dependencies

## Quick Deployment

### Method 1: Using npm script (Recommended)

1. **Configure your deployment settings:**

    ```bash
    # Edit the deployment configuration
    nano deploy.config.sh

    # Set your EC2 IP address
    export EC2_IP="1.2.3.4"  # Replace with your actual IP
    ```

2. **Deploy using npm:**

    ```bash
    # Quick deployment with default settings
    npm run deploy -- --ip YOUR_EC2_IP

    # Or use the production deployment command
    npm run deploy:prod -- --ip YOUR_EC2_IP --key ~/.ssh/your-key.pem
    ```

### Method 2: Direct script execution

1. **Make the script executable:**

    ```bash
    chmod +x deploy-ec2.sh
    ```

2. **Run the deployment:**

    ```bash
    # Basic deployment
    ./deploy-ec2.sh --ip YOUR_EC2_IP

    # With custom SSH key
    ./deploy-ec2.sh --ip YOUR_EC2_IP --key ~/.ssh/your-key.pem

    # With custom port and user
    ./deploy-ec2.sh --ip YOUR_EC2_IP --port 3333 --user ubuntu
    ```

## Deployment Script Options

```bash
./deploy-ec2.sh [OPTIONS]

Options:
  --ip <IP>          Set EC2 IP address (required)
  --key <PATH>       Set SSH key path (default: /.ssh/id_rsa)
  --user <USER>      Set SSH user (default: ubuntu)
  --port <PORT>      Set application port (default: 3333)
  --help             Show help message
```

## What the Deployment Script Does

1. **Prerequisites Check**: Validates SSH key, rsync, and ssh availability
2. **SSH Connection Test**: Tests connection to your EC2 instance
3. **Directory Setup**: Creates `/home/ubuntu/ffmeg-builder` directory structure
4. **File Sync**: Syncs your local code to EC2 (excludes node_modules, logs, etc.)
5. **Dependencies**: Installs Node.js 18, PM2, and npm dependencies
6. **FFmpeg Installation**: Installs FFmpeg if not present
7. **PM2 Configuration**: Creates and configures ecosystem.config.js
8. **Process Management**: Starts or restarts the application with PM2
9. **Firewall**: Configures UFW to allow the application port
10. **Verification**: Tests if the application is responding

## Directory Structure on EC2

After deployment, your application will be located at:

```
/home/ubuntu/ffmeg-builder/
├── server.js
├── package.json
├── ecosystem.config.js
├── public/
├── deploy/
├── output/           # FFmpeg output files
├── logs/            # Application logs
└── node_modules/    # Dependencies
```

## Post-Deployment

### Accessing Your Application

-   Application URL: `http://YOUR_EC2_IP:3333`
-   Health check: `http://YOUR_EC2_IP:3333/api/health`

### Managing the Application

```bash
# SSH into your EC2 instance
ssh -i /.ssh/id_rsa ubuntu@YOUR_EC2_IP

# Check PM2 status
pm2 status

# View application logs
pm2 logs ffmeg-builder

# Restart the application
pm2 restart ffmeg-builder

# Monitor resources
pm2 monit

# Stop the application
pm2 stop ffmeg-builder
```

### Updating the Application

To deploy updates, simply run the deployment script again:

```bash
npm run deploy -- --ip YOUR_EC2_IP
```

The script will:

-   Sync new files
-   Install any new dependencies
-   Restart the application automatically

## Troubleshooting

### Common Issues

#### 1. SSH Connection Failed

```bash
# Check if your key has correct permissions
chmod 600 /.ssh/id_rsa

# Test SSH connection manually
ssh -i /.ssh/id_rsa ubuntu@YOUR_EC2_IP

# Check security group allows SSH on port 22
```

#### 2. Application Not Responding

```bash
# SSH into EC2 and check PM2 status
ssh -i /.ssh/id_rsa ubuntu@YOUR_EC2_IP
pm2 status
pm2 logs ffmeg-builder

# Check if port is open
sudo ufw status
```

#### 3. FFmpeg Not Working

```bash
# Check FFmpeg installation
ffmpeg -version

# Reinstall if needed
sudo apt-get update
sudo apt-get install -y ffmpeg
```

#### 4. Permission Issues

```bash
# Fix ownership on EC2
sudo chown -R ubuntu:ubuntu /home/ubuntu/ffmeg-builder
```

### Viewing Logs

```bash
# Application logs via PM2
pm2 logs ffmeg-builder

# Raw log files
tail -f /home/ubuntu/ffmeg-builder/logs/combined.log
tail -f /home/ubuntu/ffmeg-builder/logs/error.log
```

## Security Considerations

1. **Firewall**: Only open necessary ports (22 for SSH, 3333 for application)
2. **SSH Keys**: Use strong SSH key pairs and never share private keys
3. **Updates**: Keep your EC2 instance updated with security patches
4. **SSL**: Consider setting up SSL/TLS for production deployments
5. **Access**: Limit SSH access to specific IP addresses if possible

## Environment Variables

The deployment script automatically configures these environment variables:

```javascript
// ecosystem.config.js
env_production: {
  NODE_ENV: 'production',
  PORT: 3333,
  OUTPUT_PATH: '/home/ubuntu/ffmeg-builder/output',
  LOG_FILE_PATH: '/home/ubuntu/ffmeg-builder/logs'
}
```

## Monitoring

### PM2 Monitoring

```bash
# Real-time monitoring
pm2 monit

# Process information
pm2 show ffmeg-builder

# Restart on file changes (development)
pm2 restart ffmeg-builder --watch
```

### System Monitoring

```bash
# Disk usage
df -h

# Memory usage
free -h

# CPU usage
htop
```

## Backup and Recovery

### Creating Backups

```bash
# Backup application directory
tar -czf ffmeg-builder-backup-$(date +%Y%m%d).tar.gz /home/ubuntu/ffmeg-builder

# Backup PM2 configuration
pm2 save
```

### Restoring from Backup

```bash
# Extract backup
tar -xzf ffmeg-builder-backup-YYYYMMDD.tar.gz

# Restore PM2 processes
pm2 resurrect
```

## Support

If you encounter issues:

1. Check the troubleshooting section above
2. Review the deployment logs
3. Verify all prerequisites are met
4. Test SSH connection manually
5. Check EC2 security groups and network ACLs

For additional help, refer to the main README.md file or check the application logs for specific error messages.
