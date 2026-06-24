# Base image
FROM ubuntu:22.04

# Set environment to non-interactive
ENV DEBIAN_FRONTEND=noninteractive

# Install dependencies
RUN apt-get update && \
    apt-get install -y \
        libdbi-perl \
        libdbd-pg-perl \
        libdigest-md4-perl \
        libredis-perl \
        inetutils-ping \
        curl \
        netcat-openbsd \
        dnsutils \
        libjson-perl \
        supervisor \
        freeradius-utils && \
    apt-get install -f -y && \
    apt-get clean
 
# Copy and install the Radiator .deb package
COPY radiator_4.23-3_all.deb /tmp/
RUN dpkg -i /tmp/radiator_4.23-3_all.deb || apt-get install -f -y

# Create config directory
RUN mkdir -p /etc/radiator

# Copy configuration and certificates
COPY radiator.conf /etc/radiator/
COPY certs/ /etc/radiator/certs/
COPY dictionary /opt/radiator/radiator/
COPY AuthApolloDeviceManager.pm /opt/radiator/radiator/Radius/
#COPY .env /etc/radiator

RUN mkdir -p /var/log/radiator \
 && chmod 777 /var/log/radiator \
 && mkdir -p /var/log/supervisor

# Copy supervisord configuration
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Expose RADIUS port (default is 1812/UDP for auth, 1813/UDP for accounting)
EXPOSE 1812/udp 1813/udp

# Start supervisord to manage radiator process
CMD ["/bin/bash", "-c", "/opt/radiator/radiator/radiusd -config_file /etc/radiator/radiator.conf & tail -F /var/log/radiator/radiator.log /var/log/radiator/session_debug.log"]
#CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
