# Build stage
FROM golang:1.23-alpine AS builder

WORKDIR /app

# Install dependencies
RUN apk add --no-cache git

# Copy all source files
COPY . .

# Download dependencies (generate go.sum if missing)
RUN go mod tidy && go mod download

# Build
RUN CGO_ENABLED=0 GOOS=linux go build -o /api ./cmd/api

# Run stage
FROM alpine:3.19

WORKDIR /app

# Install ca-certificates for HTTPS and curl for healthcheck
RUN apk add --no-cache ca-certificates curl

# Copy binary and static files
COPY --from=builder /api .
COPY admin/ ./admin/
COPY webapp/ ./webapp/
COPY templates/ ./templates/
COPY static/ ./static/

# Create non-root user
RUN adduser -D -g '' appuser
USER appuser

EXPOSE 8080

CMD ["./api"]
