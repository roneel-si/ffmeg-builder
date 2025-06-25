#!/bin/bash

# FFmpeg Builder EC2 Deployment Script
# This script deploys the application to an EC2 instance

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
EC2_IP="XX.XX.XX.XX"
SSH_KEY_PATH="/.ssh/id_rsa"
EC2_USER="ubuntu"
APP_NAME="ffmeg-builder"
REMOTE_DIR="/home/$EC2_USER/$APP_NAME"
NODE_PORT="3333"

# Utility functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required tools are installed
check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if SSH key exists
    if [ ! -f "$SSH_KEY_PATH" ]; then
        log_error "SSH key not found at $SSH_KEY_PATH"
        exit 1
    fi
    
    # Check if rsync is installed
    if ! command -v rsync &> /dev/null; then
        log_error "rsync is required but not installed. Please install rsync first."
        exit 1
    fi
    
    # Check if ssh is available
    if ! command -v ssh &> /dev/null; then
        log_error "ssh is required but not installed."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

# Test SSH connection
test_ssh_connection() {
    log_info "Testing SSH connection to $EC2_IP..."
    
    if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$EC2_USER@$EC2_IP" "echo 'SSH connection successful'" > /dev/null 2>&1; then
        log_success "SSH connection to EC2 instance successful"
    else
        log_error "Failed to connect to EC2 instance. Please check:"
        log_error "  1. EC2 IP address: $EC2_IP"
        log_error "  2. SSH key path: $SSH_KEY_PATH"
        log_error "  3. Security group allows SSH (port 22)"
        log_error "  4. Instance is running"
        exit 1
    fi
}

# Create remote directory structure
create_remote_directories() {
    log_info "Creating remote directory structure..."
    
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$EC2_USER@$EC2_IP" << EOF
        # Create application directory
        mkdir -p $REMOTE_DIR
        
        # Create output and logs directories
        mkdir -p $REMOTE_DIR/output
        mkdir -p $REMOTE_DIR/logs
        
        echo "Remote directories created successfully"
EOF
    
    log_success "Remote directory structure created"
}

# Sync application files to EC2
sync_files() {
    log_info "Syncing application files to EC2..."
    
    # Exclude unnecessary files and directories
    rsync -avz --delete \
        --exclude 'node_modules' \
        --exclude '.git' \
        --exclude '.DS_Store' \
        --exclude '*.log' \
        --exclude 'output/*' \
        --exclude 'logs/*' \
        --exclude '.env' \
        -e "ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=no" \
        ./ "$EC2_USER@$EC2_IP:$REMOTE_DIR/"
    
    log_success "Files synced successfully"
}

# Install Node.js and dependencies on EC2
install_dependencies() {
    log_info "Installing Node.js and dependencies on EC2..."
    
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$EC2_USER@$EC2_IP" << EOF
        cd $REMOTE_DIR
        
        # Check if Node.js is installed
        if ! command -v node &> /dev/null; then
            echo "Installing Node.js..."
            curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
            sudo apt-get install -y nodejs
        else
            echo "Node.js is already installed: \$(node --version)"
        fi
        
        # Check if PM2 is installed globally
        if ! command -v pm2 &> /dev/null; then
            echo "Installing PM2 globally..."
            sudo npm install -g pm2
        else
            echo "PM2 is already installed: \$(pm2 --version)"
        fi
        
        # Install application dependencies
        echo "Installing application dependencies..."
        npm install --production
        
        echo "Dependencies installation completed"
EOF
    
    log_success "Dependencies installed successfully"
}

# Create ecosystem.config.js for PM2
create_ecosystem_config() {
    log_info "Creating PM2 ecosystem configuration..."
    
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$EC2_USER@$EC2_IP" << EOF
        cd $REMOTE_DIR
        
        # Create ecosystem.config.js file
        cat > ecosystem.config.js << 'EOL'
module.exports = {
  apps: [{
    name: '$APP_NAME',
    script: 'server.js',
    instances: 1,
    exec_mode: 'cluster',
    env: {
      NODE_ENV: 'development',
      PORT: $NODE_PORT,
      OUTPUT_PATH: '$REMOTE_DIR/output',
      LOG_FILE_PATH: '$REMOTE_DIR/logs'
    },
    env_production: {
      NODE_ENV: 'production',
      PORT: $NODE_PORT,
      OUTPUT_PATH: '$REMOTE_DIR/output',
      LOG_FILE_PATH: '$REMOTE_DIR/logs'
    },
    error_file: '$REMOTE_DIR/logs/error.log',
    out_file: '$REMOTE_DIR/logs/out.log',
    log_file: '$REMOTE_DIR/logs/combined.log',
    time: true,
    max_restarts: 10,
    min_uptime: '10s',
    max_memory_restart: '500M',
    watch: false,
    ignore_watch: ['node_modules', 'logs', 'output']
  }]
};
EOL
        
        echo "Ecosystem configuration created"
EOF
    
    log_success "PM2 ecosystem configuration created"
}

# Start or restart the application with PM2
manage_pm2_process() {
    log_info "Managing PM2 process..."
    
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$EC2_USER@$EC2_IP" << EOF
        cd $REMOTE_DIR
        
        # Check if the app is already running with PM2
        if pm2 describe $APP_NAME > /dev/null 2>&1; then
            echo "Application is already running. Restarting..."
            pm2 restart $APP_NAME
            pm2 reload $APP_NAME
        else
            echo "Starting application for the first time..."
            pm2 start ecosystem.config.js --env production
        fi
        
        # Save PM2 configuration
        pm2 save
        
        # Setup PM2 to start on system boot (only run once)
        if ! systemctl is-enabled pm2-$EC2_USER > /dev/null 2>&1; then
            echo "Setting up PM2 startup script..."
            pm2 startup systemd -u $EC2_USER --hp /home/$EC2_USER
        fi
        
        # Show PM2 status
        echo "PM2 Status:"
        pm2 status
        
        echo "Application management completed"
EOF
    
    log_success "PM2 process managed successfully"
}

# Install FFmpeg if not present
install_ffmpeg() {
    log_info "Checking and installing FFmpeg..."
    
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$EC2_USER@$EC2_IP" << EOF
        # Check if FFmpeg is installed
        if ! command -v ffmpeg &> /dev/null; then
            echo "Installing FFmpeg..."
            sudo apt-get update
            sudo apt-get install -y ffmpeg
            echo "FFmpeg installed successfully"
        else
            echo "FFmpeg is already installed: \$(ffmpeg -version | head -n1)"
        fi
EOF
    
    log_success "FFmpeg check/installation completed"
}

# Configure firewall to allow the application port
configure_firewall() {
    log_info "Configuring firewall for port $NODE_PORT..."
    
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$EC2_USER@$EC2_IP" << EOF
        # Check if ufw is active and configure it
        if command -v ufw &> /dev/null; then
            sudo ufw allow $NODE_PORT/tcp
            echo "Firewall configured to allow port $NODE_PORT"
        else
            echo "UFW not available, skipping firewall configuration"
        fi
EOF
    
    log_success "Firewall configuration completed"
}

# Verify deployment
verify_deployment() {
    log_info "Verifying deployment..."
    
    # Wait a few seconds for the application to start
    sleep 5
    
    ssh -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=no "$EC2_USER@$EC2_IP" << EOF
        cd $REMOTE_DIR
        
        # Check if the application is responding
        if curl -s http://localhost:$NODE_PORT/api/health > /dev/null; then
            echo "✅ Application is responding on port $NODE_PORT"
            curl -s http://localhost:$NODE_PORT/api/health | jq . || echo "Health check response received"
        else
            echo "❌ Application is not responding on port $NODE_PORT"
            echo "PM2 logs:"
            pm2 logs $APP_NAME --lines 20
        fi
        
        echo ""
        echo "PM2 Process Status:"
        pm2 status
EOF
    
    log_success "Deployment verification completed"
}

# Main deployment function
deploy() {
    echo "🚀 Starting FFmpeg Builder deployment to EC2..."
    echo "📋 Configuration:"
    echo "   EC2 IP: $EC2_IP"
    echo "   SSH Key: $SSH_KEY_PATH"
    echo "   Remote Directory: $REMOTE_DIR"
    echo "   Application Port: $NODE_PORT"
    echo ""
    
    check_prerequisites
    test_ssh_connection
    create_remote_directories
    sync_files
    install_dependencies
    install_ffmpeg
    create_ecosystem_config
    manage_pm2_process
    configure_firewall
    verify_deployment
    
    echo ""
    log_success "🎉 Deployment completed successfully!"
    echo ""
    echo "📋 Next steps:"
    echo "   1. Access your application at: http://$EC2_IP:$NODE_PORT"
    echo "   2. Check logs: ssh -i $SSH_KEY_PATH $EC2_USER@$EC2_IP 'pm2 logs $APP_NAME'"
    echo "   3. Monitor: ssh -i $SSH_KEY_PATH $EC2_USER@$EC2_IP 'pm2 monit'"
    echo ""
    echo "📚 Useful commands:"
    echo "   PM2 status: ssh -i $SSH_KEY_PATH $EC2_USER@$EC2_IP 'pm2 status'"
    echo "   Restart app: ssh -i $SSH_KEY_PATH $EC2_USER@$EC2_IP 'pm2 restart $APP_NAME'"
    echo "   View logs: ssh -i $SSH_KEY_PATH $EC2_USER@$EC2_IP 'pm2 logs $APP_NAME'"
}

# Show usage information
show_usage() {
    echo "FFmpeg Builder EC2 Deployment Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --ip <IP>          Set EC2 IP address (default: $EC2_IP)"
    echo "  --key <PATH>       Set SSH key path (default: $SSH_KEY_PATH)"
    echo "  --user <USER>      Set SSH user (default: $EC2_USER)"
    echo "  --port <PORT>      Set application port (default: $NODE_PORT)"
    echo "  --help             Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Deploy with default settings"
    echo "  $0 --ip 1.2.3.4 --port 4000         # Deploy to specific IP and port"
    echo "  $0 --key ~/.ssh/my-key.pem          # Use different SSH key"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --ip)
                EC2_IP="$2"
                shift 2
                ;;
            --key)
                SSH_KEY_PATH="$2"
                shift 2
                ;;
            --user)
                EC2_USER="$2"
                shift 2
                ;;
            --port)
                NODE_PORT="$2"
                shift 2
                ;;
            --help)
                show_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    # Update REMOTE_DIR if EC2_USER changed
    REMOTE_DIR="/home/$EC2_USER/$APP_NAME"
}

# Main script execution
main() {
    parse_arguments "$@"
    
    # Validate required parameters
    if [ "$EC2_IP" = "XX.XX.XX.XX" ]; then
        log_error "Please set a valid EC2 IP address using --ip option"
        show_usage
        exit 1
    fi
    
    deploy
}

# Run main function with all arguments
main "$@" 