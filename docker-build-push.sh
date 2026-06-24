#!/bin/bash

# Docker Build and Push Script for AIS Radiator
# This script builds the Docker image and pushes it to Docker Hub

set -e  # Exit on any error

# Configuration
IMAGE_NAME="marcandres888/ais-radiator"
TAG="${1:-latest}"  # Default to 'latest' if no tag provided
USER_NAME="${2:-marcandres888}"  # Default Docker Hub username
USER_PASSWORD="${3:-dondon888168392}"  # Docker Hub password (optional)

echo "=================================================="
echo "AIS Radiator - Docker Build & Push"
echo "=================================================="
echo "Image: $IMAGE_NAME:$TAG"
echo ""

# Check if Docker is running
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker is not running. Please start Docker and try again."
    exit 1
fi

# Check if logged in to Docker Hub
if ! docker info 2>&1 | grep -q "Username"; then
    docker login -u $USER_NAME -p $USER_PASSWORD
fi


# Build the image
echo "🔨 Building Docker image..."
docker build -t "$IMAGE_NAME:$TAG" .

if [ $? -eq 0 ]; then
    echo "✅ Build successful!"
else
    echo "❌ Build failed!"
    exit 1
fi

# Tag as latest if building a version tag
if [ "$TAG" != "latest" ]; then
    echo ""
    echo "🏷️  Tagging as latest..."
    docker tag "$IMAGE_NAME:$TAG" "$IMAGE_NAME:latest"
fi

# Push to Docker Hub
echo ""
echo "📤 Pushing to Docker Hub..."
docker push "$IMAGE_NAME:$TAG"

if [ $? -eq 0 ]; then
    echo "✅ Push successful: $IMAGE_NAME:$TAG"
else
    echo "❌ Push failed!"
    exit 1
fi

# Push latest tag if we created it
if [ "$TAG" != "latest" ]; then
    echo ""
    echo "📤 Pushing latest tag..."
    docker push "$IMAGE_NAME:latest"
    
    if [ $? -eq 0 ]; then
        echo "✅ Push successful: $IMAGE_NAME:latest"
    else
        echo "❌ Push failed for latest tag!"
        exit 1
    fi
fi

echo ""
echo "=================================================="
echo "✅ All Done!"
echo "=================================================="
echo "Images available at:"
echo "  - $IMAGE_NAME:$TAG"
if [ "$TAG" != "latest" ]; then
    echo "  - $IMAGE_NAME:latest"
fi
echo ""
echo "To run on production:"
echo "  docker pull $IMAGE_NAME:$TAG"
echo "  docker run -d --name ais-radiator \\"
echo "    --restart unless-stopped \\"
echo "    -p 1812:1812/udp \\"
echo "    -p 1813:1813/udp \\"
echo "    -e DATABASE_URL=postgresql://user:pass@host:5432/radius \\"
echo "    $IMAGE_NAME:$TAG"
echo ""
echo "Or use docker-compose for deployment"
echo "=================================================="
