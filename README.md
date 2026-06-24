# AIS Radiator - RADIUS Server

RADIUS authentication server for Apollo Internet Services, built on Radiator with custom Perl modules for integration with Apollo Device Provisioner API.

## 🏗️ Architecture

**Components:**
- **Radiator 4.23:** Commercial-grade RADIUS server
- **AuthApolloDeviceManager.pm:** Custom Perl module for Apollo API integration
- **Docker Container:** Containerized deployment for Kubernetes

**Authentication Flow:**
1. RADIUS request received (NAS, PPPoE, etc.)
2. AuthApolloDeviceManager extracts credentials
3. API call to Apollo Device Provisioner for validation
4. Response sent back to RADIUS client

## 🚀 Quick Start

### Local Development

```bash
# Build Docker image
./docker-build-push.sh

# Run with docker-compose
docker-compose up -d

# View logs
docker-compose logs -f
```

### Kubernetes Deployment

Deployed as part of Apollo Internet Services stack:

```yaml
# Service: ais-radiator (in apollo-internet-services-deployment)
Type: LoadBalancer
Ports: 1812/UDP (auth), 1813/UDP (accounting)
```

## 📋 Configuration

### Environment Variables

Set in `apollo-config` ConfigMap:

```yaml
APOLLO_PROVISIONER_URL: http://apollo-device-provisioner:8000/api/v1
```

### RADIUS Shared Secret

Set in `apollo-secrets`:

```yaml
RADIUS_SHARED_SECRET: your-secret-here
```

### Radiator Configuration

Main configuration: `radiator.conf`
- Listen ports: 1812 (auth), 1813 (accounting)
- Dictionary: `/opt/radiator/radiator/dictionary`
- Logs: `/var/log/radiator/radiator.log`

## 🔧 Custom Auth Module

`AuthApolloDeviceManager.pm` - Perl module for Apollo integration

**Features:**
- PPPoE username/password validation
- API integration with Device Provisioner
- Session management
- Logging and debugging

**API Endpoint:**
```
POST /api/v1/radius/authenticate
{
  "username": "pppoe_user",
  "password": "pppoe_pass"
}
```

## 🐳 Docker Configuration

### Dockerfile

```dockerfile
FROM debian:bullseye-slim
# Install Radiator
# Copy custom modules
# Configure logging
```

### Build and Push

```bash
./docker-build-push.sh

# Options:
# - Builds image: marcandres888/ais-radiator:latest
# - Pushes to Docker Hub
# - Tags with version
```

## 📊 Testing

### Local Testing

```bash
# Install radtest
apt-get install freeradius-utils

# Test authentication
radtest pppoe_user pppoe_pass localhost 0 mysecret

# Expected output:
# Received Access-Accept Id <id> from 127.0.0.1:1812 to 127.0.0.1:xxxxx length 20
```

### Kubernetes Testing

```bash
# Get LoadBalancer IP
kubectl get svc -n ais-sandbox ais-radiator

# Test from external host
radtest username password <LOADBALANCER_IP> 0 mysecret

# Check logs
kubectl logs -n ais-sandbox -l app=ais-radiator -f
```

## 🔍 Debugging

### Enable Debug Logging

In `radiator.conf`:
```
Trace 4  # Maximum debug level
```

### View Logs

```bash
# Docker
docker-compose logs -f

# Kubernetes
kubectl logs -n ais-sandbox -l app=ais-radiator -f

# Container
docker exec -it ais-radiator tail -f /var/log/radiator/radiator.log
```

### Common Issues

**Authentication Failures:**
- Check Apollo Device Provisioner API connectivity
- Verify RADIUS shared secret matches
- Check NAS IP address whitelist
- Review Perl module logs

**Connection Refused:**
- Verify ports 1812/1813 are open
- Check LoadBalancer IP allocation
- Verify service type (LoadBalancer with UDP)

## 📁 File Structure

```
ais-radiator/
├── AuthApolloDeviceManager.pm  # Custom Perl auth module
├── radiator.conf               # Main configuration
├── dictionary                  # RADIUS attributes
├── Dockerfile                 # Container build
├── docker-compose.yaml        # Local deployment
├── docker-build-push.sh       # Build script
├── certs/                     # SSL certificates (not committed)
├── logs/                      # Runtime logs (not committed)
└── radiator_files/            # Additional Radiator files
```

## 🔐 Security Considerations

1. **Shared Secrets:** Change default RADIUS secrets
2. **NAS IP Whitelist:** Restrict trusted RADIUS clients
3. **API Authentication:** Secure Apollo Device Provisioner API
4. **Certificates:** Use proper SSL/TLS certificates
5. **Network Policies:** Limit pod-to-pod communication
6. **Audit Logs:** Monitor authentication attempts

## 🚀 CI/CD Integration

### GitLab CI Example

```yaml
build:radiator:
  stage: build
  script:
    - docker build -t marcandres888/ais-radiator:$CI_COMMIT_SHA .
    - docker push marcandres888/ais-radiator:$CI_COMMIT_SHA
  only:
    - main

deploy:radiator:
  stage: deploy
  script:
    - kubectl set image deployment/ais-radiator -n ais-sandbox \
        ais-radiator=marcandres888/ais-radiator:$CI_COMMIT_SHA
  environment:
    name: sandbox
  only:
    - main
```

## 📊 Monitoring

### Metrics to Monitor

- Authentication success/failure rate
- Response time
- Active sessions
- NAS connection status
- API call latency to Device Provisioner

### Health Checks

```bash
# Check if RADIUS is listening
netstat -ulpn | grep radiator

# Test authentication
radtest test test localhost 0 mysecret

# Check process
ps aux | grep radiator
```

## 🔄 Updates

### Update Radiator Version

1. Update `radiator_4.23-3_all.deb` in repository
2. Rebuild Docker image
3. Test in development
4. Deploy to production

### Update Custom Module

1. Modify `AuthApolloDeviceManager.pm`
2. Test locally with docker-compose
3. Commit changes
4. Rebuild and deploy

## 📚 References

- [Radiator Official Documentation](https://radiatorsoftware.com/)
- [RADIUS Protocol RFC 2865](https://tools.ietf.org/html/rfc2865)
- [Radiator Perl API](https://radiatorsoftware.com/radiator-perl-api/)

## 📝 License

Copyright © Apollo Global. All rights reserved.

## 📧 Support

For issues or questions, contact the Apollo infrastructure team.

---

**Version:** 1.0.0  
**Last Updated:** November 18, 2025  
**Maintained by:** Apollo DevOps Team
