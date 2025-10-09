# Build stage
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY api/go.mod ./
COPY api/go.sum ./
RUN go mod download
COPY api/ .
RUN CGO_ENABLED=0 GOOS=linux go build -o /main .

# Final stage
FROM alpine:latest
WORKDIR /
COPY --from=builder /main /main
EXPOSE 8080
CMD ["/main"]
