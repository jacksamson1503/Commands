# Lightweight Alpine Linux Nginx image (ideal for t3.micro & 8GB storage)
FROM nginx:alpine

# Copy custom Nginx configuration (includes /health endpoint)
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Remove default nginx static assets
RUN rm -rf /usr/share/nginx/html/*

# Copy application static files
COPY index.html /usr/share/nginx/html/

# Expose port 80 inside container
EXPOSE 80

# Start Nginx in foreground
CMD ["nginx", "-g", "daemon off;"]
