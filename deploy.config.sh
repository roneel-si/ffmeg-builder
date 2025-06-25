#!/bin/bash

# FFmpeg Builder Deployment Configuration
# Modify these values according to your EC2 setup

# EC2 Instance Configuration
export EC2_IP="XX.XX.XX.XX"          # Replace with your EC2 public IP
export SSH_KEY_PATH="/.ssh/id_rsa"    # Path to your SSH private key
export EC2_USER="ubuntu"              # EC2 username (ubuntu for Ubuntu AMI)

# Application Configuration
export APP_NAME="ffmeg-builder"       # Application name for PM2
export NODE_PORT="3333"               # Port number for the Node.js application
export REMOTE_DIR="/home/$EC2_USER/$APP_NAME"  # Remote directory path

# Deployment Options
export INSTALL_FFMPEG="true"          # Whether to install FFmpeg
export CONFIGURE_FIREWALL="true"      # Whether to configure firewall
export BACKUP_EXISTING="false"        # Whether to backup existing deployment

# Example configurations for different environments:

# Development Environment
# export EC2_IP="1.2.3.4"
# export NODE_PORT="3333"
# export SSH_KEY_PATH="~/.ssh/dev-key.pem"

# Production Environment  
# export EC2_IP="5.6.7.8"
# export NODE_PORT="3333"
# export SSH_KEY_PATH="~/.ssh/prod-key.pem"

# Staging Environment
# export EC2_IP="9.10.11.12"
# export NODE_PORT="3333"
# export SSH_KEY_PATH="~/.ssh/staging-key.pem"

echo "Deployment configuration loaded:"
echo "  EC2 IP: $EC2_IP"
echo "  SSH Key: $SSH_KEY_PATH"
echo "  Port: $NODE_PORT"
echo "  User: $EC2_USER"
echo "  App Name: $APP_NAME" 