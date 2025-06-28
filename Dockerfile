FROM alpine:3.22
ARG TARGETPLATFORM
WORKDIR /app
COPY artifacts/$TARGETPLATFORM/tress /usr/local/bin/tress
RUN chmod +x /usr/local/bin/tress
CMD ["/usr/local/bin/tress"]
