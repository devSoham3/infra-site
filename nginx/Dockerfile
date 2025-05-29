FROM nginx:latest

# Install apache2-utils for htpasswd command
RUN apt-get update && apt-get install -y apache2-utils && rm -rf /var/lib/apt/lists/*

# Copy the script to the correct location
COPY generate-htpasswd.sh /docker-entrypoint.d/
RUN chmod +x /docker-entrypoint.d/generate-htpasswd.sh