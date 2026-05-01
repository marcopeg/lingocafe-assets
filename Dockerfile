FROM nginx:1.27-alpine

LABEL org.opencontainers.image.title="lingocafe-assets"
LABEL org.opencontainers.image.description="Nginx image for serving immutable static assets"

COPY nginx.conf /etc/nginx/nginx.conf

RUN rm -rf /usr/share/nginx/html/*

COPY src/ /usr/share/nginx/html/

RUN find /usr/share/nginx/html -type d -exec chmod 755 {} + \
  && find /usr/share/nginx/html -type f -exec chmod 644 {} +

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q --spider http://127.0.0.1/healthz || exit 1
