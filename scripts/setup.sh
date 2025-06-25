#!/bin/bash

# FFmpeg Builder Setup Script
# This script helps set up and run the application in different modes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check system requirements
check_requirements() {
    log_info "Checking system requirements..."
    
    # Check Node.js
    if command_exists node; then
        NODE_VERSION=$(node --version | cut -d'v' -f2)
        log_success "Node.js version: $NODE_VERSION"
        
        # Check if version is >= 18
        if [ "$(printf '%s\n' "18.0.0" "$NODE_VERSION" | sort -V | head -n1)" != "18.0.0" ]; then
            log_error "Node.js 18.0 or higher is required"
            exit 1
        fi
    else
        log_error "Node.js is not installed"
        exit 1
    fi
    
    # Check npm
    if command_exists npm; then
        NPM_VERSION=$(npm --version)
        log_success "npm version: $NPM_VERSION"
    else
        log_error "npm is not installed"
        exit 1
    fi
    
    # Check FFmpeg
    if command_exists ffmpeg; then
        FFMPEG_VERSION=$(ffmpeg -version | head -n1 | cut -d' ' -f3)
        log_success "FFmpeg version: $FFMPEG_VERSION"
    else
        log_warning "FFmpeg is not installed - required for conversions"
    fi
    
    # Check Docker (optional)
    if command_exists docker; then
        DOCKER_VERSION=$(docker --version | cut -d' ' -f3 | sed 's/,//')
        log_success "Docker version: $DOCKER_VERSION"
    else
        log_info "Docker is not installed (optional)"
    fi
}

# Install dependencies
install_dependencies() {
    log_info "Installing Node.js dependencies..."
    
    if [ -f "package-lock.json" ]; then
        npm ci
    else
        npm install
    fi
    
    log_success "Dependencies installed successfully"
}

# Setup environment
setup_environment() {
    log_info "Setting up environment configuration..."
    
    if [ ! -f ".env" ]; then
        if [ -f "env.example" ]; then
            cp env.example .env
            log_success "Environment file created from template"
        else
            log_warning "No env.example file found, creating basic .env"
            cat > .env << EOF
NODE_ENV=development
PORT=3000
OUTPUT_PATH=./output
LOG_LEVEL=info
EOF
        fi
    else
        log_info "Environment file already exists"
    fi
    
    # Create output directory
    mkdir -p output logs
    log_success "Output directories created"
}

# Development mode
start_development() {
    log_info "Starting development server..."
    
    check_requirements
    install_dependencies
    setup_environment
    
    log_info "Development server starting on http://localhost:3000"
    
    if command_exists nodemon; then
        nodemon server.js
    else
        log_warning "nodemon not found globally, using node directly"
        node server.js
    fi
}

# Production mode
start_production() {
    log_info "Starting production server..."
    
    check_requirements
    install_dependencies
    setup_environment
    
    # Set production environment
    export NODE_ENV=production
    
    if command_exists pm2; then
        log_info "Starting with PM2..."
        pm2 start ecosystem.config.js --env production
        pm2 save
        log_success "Application started with PM2"
    else
        log_warning "PM2 not found, starting with node directly"
        node server.js
    fi
}

# Docker mode
start_docker() {
    log_info "Starting with Docker..."
    
    if ! command_exists docker; then
        log_error "Docker is not installed"
        exit 1
    fi
    
    if command_exists docker-compose; then
        log_info "Using Docker Compose..."
        docker-compose up --build -d
        log_success "Application started with Docker Compose"
        log_info "Application available at http://localhost"
    else
        log_info "Using Docker directly..."
        docker build -t ffmpeg-builder .
        docker run -d -p 3000:3000 --name ffmpeg-builder-app ffmpeg-builder
        log_success "Application started with Docker"
        log_info "Application available at http://localhost:3000"
    fi
}

# Stop services
stop_services() {
    log_info "Stopping services..."
    
    # Stop PM2 processes
    if command_exists pm2; then
        pm2 stop ffmpeg-builder 2>/dev/null || true
        pm2 delete ffmpeg-builder 2>/dev/null || true
        log_info "PM2 processes stopped"
    fi
    
    # Stop Docker containers
    if command_exists docker; then
        docker stop ffmpeg-builder-app 2>/dev/null || true
        docker rm ffmpeg-builder-app 2>/dev/null || true
        
        if command_exists docker-compose; then
            docker-compose down 2>/dev/null || true
        fi
        log_info "Docker containers stopped"
    fi
    
    log_success "All services stopped"
}

# Install FFmpeg
install_ffmpeg() {
    log_info "Installing FFmpeg..."
    
    if [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        if command_exists apt-get; then
            sudo apt-get update
            sudo apt-get install -y ffmpeg
        elif command_exists yum; then
            sudo yum install -y ffmpeg
        elif command_exists apk; then
            sudo apk add ffmpeg
        else
            log_error "Package manager not supported. Please install FFmpeg manually."
            exit 1
        fi
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command_exists brew; then
            brew install ffmpeg
        else
            log_error "Homebrew not found. Please install FFmpeg manually or install Homebrew first."
            exit 1
        fi
    else
        log_error "Operating system not supported for automatic FFmpeg installation"
        exit 1
    fi
    
    log_success "FFmpeg installed successfully"
}

# Show status
show_status() {
    log_info "System Status:"
    echo
    
    # Check if app is running
    if curl -s http://localhost:3000/api/health >/dev/null 2>&1; then
        log_success "Application is running at http://localhost:3000"
    else
        log_warning "Application is not responding"
    fi
    
    # PM2 status
    if command_exists pm2; then
        echo
        log_info "PM2 Status:"
        pm2 status 2>/dev/null || log_info "No PM2 processes running"
    fi
    
    # Docker status
    if command_exists docker; then
        echo
        log_info "Docker Status:"
        docker ps --filter "name=ffmpeg-builder" 2>/dev/null || log_info "No Docker containers running"
    fi
    
    # System resources
    echo
    log_info "System Resources:"
    echo "Disk space: $(df -h . | tail -1 | awk '{print $4}') available"
    echo "Memory: $(free -h 2>/dev/null | grep Mem | awk '{print $7}' || echo 'N/A') available"
}

# Show usage
show_usage() {
    echo "FFmpeg Builder Setup Script"
    echo
    echo "Usage: $0 [COMMAND]"
    echo
    echo "Commands:"
    echo "  dev         Start development server"
    echo "  prod        Start production server"
    echo "  docker      Start with Docker"
    echo "  stop        Stop all services"
    echo "  install     Install dependencies"
    echo "  ffmpeg      Install FFmpeg"
    echo "  status      Show system status"
    echo "  check       Check system requirements"
    echo "  help        Show this help message"
    echo
    echo "Examples:"
    echo "  $0 dev      # Start development server"
    echo "  $0 prod     # Start production server"
    echo "  $0 docker   # Start with Docker Compose"
    echo "  $0 stop     # Stop all services"
}

# Main script logic
case "${1:-help}" in
    "dev"|"development")
        start_development
        ;;
    "prod"|"production")
        start_production
        ;;
    "docker")
        start_docker
        ;;
    "stop")
        stop_services
        ;;
    "install")
        check_requirements
        install_dependencies
        setup_environment
        ;;
    "ffmpeg")
        install_ffmpeg
        ;;
    "status")
        show_status
        ;;
    "check")
        check_requirements
        ;;
    "help"|"--help"|"-h")
        show_usage
        ;;
    *)
        log_error "Unknown command: $1"
        echo
        show_usage
        exit 1
        ;;
esac 