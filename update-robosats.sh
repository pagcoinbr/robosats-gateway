#!/bin/bash

# RoboSats Update Script
# This script updates the RoboSats client to the latest Docker image

set -e

echo "======================================"
echo "RoboSats Client Update Script"
echo "======================================"
echo ""

# Check if docker is installed
if ! command -v docker &> /dev/null; then
    echo "Error: Docker is not installed"
    exit 1
fi

# Check if docker-compose is installed
if ! command -v docker-compose &> /dev/null; then
    echo "Error: docker-compose is not installed"
    exit 1
fi

# Get the directory where the script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "Step 1: Pulling latest RoboSats client image..."
docker pull recksato/robosats-client:latest

echo ""
echo "Step 2: Stopping and removing old container..."
CONTAINER_ID=$(docker ps -aq --filter "name=robosats-client")
if [ -n "$CONTAINER_ID" ]; then
    docker stop robosats-client 2>/dev/null || true
    docker rm robosats-client 2>/dev/null || true
    echo "Old container removed"
else
    echo "No existing container found"
fi

echo ""
echo "Step 3: Starting RoboSats client with latest image..."
docker-compose up -d robosats-client

echo ""
echo "Step 4: Checking container status..."
sleep 2
docker ps --filter "name=robosats-client" --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"

echo ""
echo "======================================"
echo "Update completed successfully!"
echo "======================================"
echo ""
echo "To view logs, run:"
echo "  docker logs -f robosats-client"
