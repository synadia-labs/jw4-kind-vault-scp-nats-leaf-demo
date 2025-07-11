# Device Client Implementation Plan

## Architecture Overview

This project implements a C-based client that simulates IoT devices connecting to the NATS leaf cluster. The client uses mTLS authentication, publishes periodic metrics, and responds to commands.

## Architecture Components

### 1. Core Components
- **NATS C Client**: Core messaging library
- **TLS Handler**: OpenSSL-based mTLS implementation
- **Metrics Generator**: Simulated sensor data
- **Command Processor**: Instruction handler
- **Configuration Manager**: Runtime settings

### 2. Communication Architecture
- **Publishing**: Periodic metrics on device-specific subjects
- **Subscribing**: Command listener for device control
- **Request/Reply**: Acknowledgment of received commands
- **Error Handling**: Reconnection and failover logic

### 3. Security Architecture
- **mTLS**: Certificate-based authentication
- **Certificate Validation**: Proper chain verification
- **Secure Storage**: Protected key material
- **Subject Isolation**: Device-specific namespaces

### 4. Data Architecture
- **Metrics Format**: JSON-encoded sensor data
- **Command Format**: Structured instruction messages
- **Timestamp**: UTC-based time tracking
- **Device Identity**: Certificate CN-based identification

## Implementation Steps

### Phase 1: Project Setup

1. **Directory Structure**
   ```
   devices/
   ├── src/
   │   ├── main.c           # Main entry point
   │   ├── nats_client.c    # NATS connection handling
   │   ├── tls_handler.c    # TLS/mTLS implementation
   │   ├── metrics.c        # Metrics generation
   │   ├── commands.c       # Command processing
   │   └── config.c         # Configuration management
   ├── include/
   │   ├── device_client.h  # Main header
   │   ├── nats_client.h    # NATS definitions
   │   ├── tls_handler.h    # TLS definitions
   │   ├── metrics.h        # Metrics structures
   │   └── commands.h       # Command structures
   ├── certs/               # Certificate storage
   ├── tests/               # Unit tests
   ├── Makefile            # Build configuration
   ├── CMakeLists.txt     # CMake configuration
   └── Dockerfile          # Container build
   ```

2. **Dependencies Setup**
   ```makefile
   # Makefile
   CC = gcc
   CFLAGS = -Wall -O2 -I./include -I/usr/local/include
   LDFLAGS = -L/usr/local/lib -lnats -lssl -lcrypto -lpthread -lm
   
   DEPS = nats.h openssl/ssl.h openssl/err.h
   LIBS = -lnats -lssl -lcrypto -lpthread -lm
   ```

### Phase 2: Core NATS Client Implementation

1. **Main Program Structure** (`src/main.c`)
   ```c
   #include <stdio.h>
   #include <stdlib.h>
   #include <string.h>
   #include <signal.h>
   #include <unistd.h>
   #include "device_client.h"
   
   static volatile int running = 1;
   
   void signal_handler(int sig) {
       running = 0;
   }
   
   int main(int argc, char *argv[]) {
       device_config_t config;
       natsConnection *conn = NULL;
       natsStatus s;
       
       // Parse command line arguments
       if (parse_arguments(argc, argv, &config) != 0) {
           print_usage(argv[0]);
           return 1;
       }
       
       // Set up signal handling
       signal(SIGINT, signal_handler);
       signal(SIGTERM, signal_handler);
       
       // Initialize NATS connection with mTLS
       s = setup_nats_connection(&conn, &config);
       if (s != NATS_OK) {
           fprintf(stderr, "Failed to connect: %s\n", 
                   natsStatus_GetText(s));
           return 1;
       }
       
       // Start metrics publisher
       pthread_t metrics_thread;
       pthread_create(&metrics_thread, NULL, 
                      metrics_publisher, conn);
       
       // Set up command subscriber
       natsSubscription *sub = NULL;
       s = setup_command_subscriber(&sub, conn, config.device_id);
       if (s != NATS_OK) {
           fprintf(stderr, "Failed to subscribe: %s\n",
                   natsStatus_GetText(s));
           natsConnection_Destroy(conn);
           return 1;
       }
       
       printf("Device %s connected and running...\n", 
              config.device_id);
       
       // Main loop
       while (running) {
           sleep(1);
           
           // Check connection status
           if (natsConnection_IsClosed(conn)) {
               fprintf(stderr, "Connection lost, exiting...\n");
               break;
           }
       }
       
       // Cleanup
       running = 0;
       pthread_join(metrics_thread, NULL);
       natsSubscription_Destroy(sub);
       natsConnection_Destroy(conn);
       
       return 0;
   }
   ```

2. **Configuration Parser** (`src/config.c`)
   ```c
   #include "config.h"
   #include <getopt.h>
   
   int parse_arguments(int argc, char *argv[], 
                      device_config_t *config) {
       int opt;
       
       // Set defaults
       config->device_id = NULL;
       config->server_url = "tls://localhost:4222";
       config->cert_file = NULL;
       config->key_file = NULL;
       config->ca_file = NULL;
       config->metrics_interval = 10;
       
       static struct option long_options[] = {
           {"device-id", required_argument, 0, 'd'},
           {"server", required_argument, 0, 's'},
           {"cert", required_argument, 0, 'c'},
           {"key", required_argument, 0, 'k'},
           {"ca", required_argument, 0, 'a'},
           {"interval", required_argument, 0, 'i'},
           {0, 0, 0, 0}
       };
       
       while ((opt = getopt_long(argc, argv, "d:s:c:k:a:i:", 
                                long_options, NULL)) != -1) {
           switch (opt) {
               case 'd':
                   config->device_id = strdup(optarg);
                   break;
               case 's':
                   config->server_url = strdup(optarg);
                   break;
               case 'c':
                   config->cert_file = strdup(optarg);
                   break;
               case 'k':
                   config->key_file = strdup(optarg);
                   break;
               case 'a':
                   config->ca_file = strdup(optarg);
                   break;
               case 'i':
                   config->metrics_interval = atoi(optarg);
                   break;
               default:
                   return -1;
           }
       }
       
       // Validate required fields
       if (!config->device_id || !config->cert_file || 
           !config->key_file || !config->ca_file) {
           fprintf(stderr, "Missing required arguments\n");
           return -1;
       }
       
       return 0;
   }
   ```

### Phase 3: TLS/mTLS Implementation

1. **TLS Handler** (`src/tls_handler.c`)
   ```c
   #include "tls_handler.h"
   #include <openssl/ssl.h>
   #include <openssl/err.h>
   
   static SSL_CTX *create_ssl_context(const char *ca_file,
                                     const char *cert_file,
                                     const char *key_file) {
       SSL_CTX *ctx;
       
       // Initialize OpenSSL
       SSL_library_init();
       SSL_load_error_strings();
       OpenSSL_add_all_algorithms();
       
       // Create context
       ctx = SSL_CTX_new(TLS_client_method());
       if (!ctx) {
           ERR_print_errors_fp(stderr);
           return NULL;
       }
       
       // Load CA certificate
       if (SSL_CTX_load_verify_locations(ctx, ca_file, NULL) != 1) {
           fprintf(stderr, "Failed to load CA certificate\n");
           SSL_CTX_free(ctx);
           return NULL;
       }
       
       // Load client certificate
       if (SSL_CTX_use_certificate_file(ctx, cert_file, 
                                       SSL_FILETYPE_PEM) != 1) {
           fprintf(stderr, "Failed to load client certificate\n");
           SSL_CTX_free(ctx);
           return NULL;
       }
       
       // Load private key
       if (SSL_CTX_use_PrivateKey_file(ctx, key_file, 
                                       SSL_FILETYPE_PEM) != 1) {
           fprintf(stderr, "Failed to load private key\n");
           SSL_CTX_free(ctx);
           return NULL;
       }
       
       // Verify private key
       if (SSL_CTX_check_private_key(ctx) != 1) {
           fprintf(stderr, "Private key does not match certificate\n");
           SSL_CTX_free(ctx);
           return NULL;
       }
       
       // Set verification mode
       SSL_CTX_set_verify(ctx, SSL_VERIFY_PEER, NULL);
       SSL_CTX_set_verify_depth(ctx, 4);
       
       return ctx;
   }
   
   natsStatus setup_tls_options(natsOptions *opts,
                               const device_config_t *config) {
       SSL_CTX *ssl_ctx;
       natsStatus s = NATS_OK;
       
       // Create SSL context
       ssl_ctx = create_ssl_context(config->ca_file,
                                    config->cert_file,
                                    config->key_file);
       if (!ssl_ctx) {
           return NATS_SSL_ERROR;
       }
       
       // Set TLS options
       s = natsOptions_SetSecure(opts, true);
       if (s == NATS_OK) {
           s = natsOptions_SetTLSCtx(opts, ssl_ctx);
       }
       
       return s;
   }
   ```

### Phase 4: NATS Connection Management

1. **Connection Setup** (`src/nats_client.c`)
   ```c
   #include "nats_client.h"
   #include "tls_handler.h"
   
   static void disconnected_cb(natsConnection *nc, void *closure) {
       printf("Disconnected from NATS server\n");
   }
   
   static void reconnected_cb(natsConnection *nc, void *closure) {
       printf("Reconnected to NATS server\n");
   }
   
   static void closed_cb(natsConnection *nc, void *closure) {
       printf("Connection closed\n");
   }
   
   natsStatus setup_nats_connection(natsConnection **conn,
                                   const device_config_t *config) {
       natsOptions *opts = NULL;
       natsStatus s;
       
       // Create options
       s = natsOptions_Create(&opts);
       if (s != NATS_OK) {
           return s;
       }
       
       // Set connection callbacks
       s = natsOptions_SetDisconnectedCB(opts, disconnected_cb, NULL);
       if (s == NATS_OK) {
           s = natsOptions_SetReconnectedCB(opts, reconnected_cb, NULL);
       }
       if (s == NATS_OK) {
           s = natsOptions_SetClosedCB(opts, closed_cb, NULL);
       }
       
       // Configure reconnection
       if (s == NATS_OK) {
           s = natsOptions_SetMaxReconnect(opts, -1); // Infinite
       }
       if (s == NATS_OK) {
           s = natsOptions_SetReconnectWait(opts, 2000); // 2 seconds
       }
       if (s == NATS_OK) {
           s = natsOptions_SetReconnectBufSize(opts, 8*1024*1024); // 8MB
       }
       
       // Set up TLS
       if (s == NATS_OK) {
           s = setup_tls_options(opts, config);
       }
       
       // Set name for connection
       if (s == NATS_OK) {
           char name[256];
           snprintf(name, sizeof(name), "device-%s", config->device_id);
           s = natsOptions_SetName(opts, name);
       }
       
       // Connect to server
       if (s == NATS_OK) {
           s = natsConnection_Connect(conn, opts);
       }
       
       // Cleanup
       natsOptions_Destroy(opts);
       
       return s;
   }
   ```

### Phase 5: Metrics Generation and Publishing

1. **Metrics Generator** (`src/metrics.c`)
   ```c
   #include "metrics.h"
   #include <time.h>
   #include <math.h>
   
   typedef struct {
       natsConnection *conn;
       const char *device_id;
       int interval;
   } metrics_context_t;
   
   static double generate_temperature() {
       // Simulate temperature between 20-30°C with some variation
       return 25.0 + (rand() % 100) / 20.0 - 2.5;
   }
   
   static double generate_cpu_usage() {
       // Simulate CPU usage between 10-90%
       return 10.0 + (rand() % 80);
   }
   
   static long generate_memory_usage() {
       // Simulate memory usage in MB
       return 100 + (rand() % 400);
   }
   
   static void generate_metrics_json(char *buffer, size_t size,
                                   const char *device_id) {
       time_t now;
       char timestamp[64];
       
       time(&now);
       strftime(timestamp, sizeof(timestamp), 
                "%Y-%m-%dT%H:%M:%SZ", gmtime(&now));
       
       snprintf(buffer, size,
           "{"
           "\"device_id\": \"%s\","
           "\"timestamp\": \"%s\","
           "\"metrics\": {"
           "  \"temperature\": %.2f,"
           "  \"cpu_usage\": %.2f,"
           "  \"memory_mb\": %ld,"
           "  \"uptime_seconds\": %ld"
           "}"
           "}",
           device_id,
           timestamp,
           generate_temperature(),
           generate_cpu_usage(),
           generate_memory_usage(),
           time(NULL) - start_time
       );
   }
   
   void* metrics_publisher(void *arg) {
       metrics_context_t *ctx = (metrics_context_t*)arg;
       char subject[256];
       char message[1024];
       natsStatus s;
       
       snprintf(subject, sizeof(subject), 
                "device.%s.metrics.telemetry", ctx->device_id);
       
       while (running) {
           // Generate metrics
           generate_metrics_json(message, sizeof(message), 
                               ctx->device_id);
           
           // Publish metrics
           s = natsConnection_PublishString(ctx->conn, 
                                          subject, message);
           if (s != NATS_OK) {
               fprintf(stderr, "Failed to publish metrics: %s\n",
                       natsStatus_GetText(s));
           } else {
               printf("Published metrics: %s\n", message);
           }
           
           // Wait for next interval
           sleep(ctx->interval);
       }
       
       return NULL;
   }
   ```

### Phase 6: Command Processing

1. **Command Handler** (`src/commands.c`)
   ```c
   #include "commands.h"
   #include <json-c/json.h>
   
   typedef struct {
       char *command;
       char *parameters;
       char *request_id;
   } device_command_t;
   
   static int parse_command(const char *data, device_command_t *cmd) {
       struct json_object *parsed;
       struct json_object *field;
       
       parsed = json_tokener_parse(data);
       if (!parsed) {
           return -1;
       }
       
       // Extract command
       if (json_object_object_get_ex(parsed, "command", &field)) {
           cmd->command = strdup(json_object_get_string(field));
       }
       
       // Extract parameters
       if (json_object_object_get_ex(parsed, "parameters", &field)) {
           cmd->parameters = strdup(json_object_to_json_string(field));
       }
       
       // Extract request ID
       if (json_object_object_get_ex(parsed, "request_id", &field)) {
           cmd->request_id = strdup(json_object_get_string(field));
       }
       
       json_object_put(parsed);
       return 0;
   }
   
   static void process_command(device_command_t *cmd, 
                              natsConnection *conn,
                              const char *device_id) {
       char response[512];
       char subject[256];
       
       printf("Received command: %s\n", cmd->command);
       
       // Process different commands
       if (strcmp(cmd->command, "reboot") == 0) {
           printf("Reboot command received - simulating reboot\n");
           snprintf(response, sizeof(response),
               "{\"status\":\"success\",\"message\":\"Reboot initiated\"}");
       } else if (strcmp(cmd->command, "update_config") == 0) {
           printf("Config update command received\n");
           snprintf(response, sizeof(response),
               "{\"status\":\"success\",\"message\":\"Config updated\"}");
       } else if (strcmp(cmd->command, "get_status") == 0) {
           snprintf(response, sizeof(response),
               "{\"status\":\"success\",\"device_status\":\"operational\"}");
       } else {
           snprintf(response, sizeof(response),
               "{\"status\":\"error\",\"message\":\"Unknown command\"}");
       }
       
       // Send response
       if (cmd->request_id) {
           snprintf(subject, sizeof(subject),
                   "device.%s.response.%s", device_id, cmd->request_id);
           natsConnection_PublishString(conn, subject, response);
       }
   }
   
   static void command_handler(natsConnection *nc, 
                              natsSubscription *sub,
                              natsMsg *msg, void *closure) {
       const char *device_id = (const char*)closure;
       device_command_t cmd = {0};
       
       printf("Command received on subject: %s\n", 
              natsMsg_GetSubject(msg));
       printf("Command data: %s\n", natsMsg_GetData(msg));
       
       // Parse command
       if (parse_command(natsMsg_GetData(msg), &cmd) == 0) {
           process_command(&cmd, nc, device_id);
           
           // Cleanup
           free(cmd.command);
           free(cmd.parameters);
           free(cmd.request_id);
       } else {
           fprintf(stderr, "Failed to parse command\n");
       }
       
       natsMsg_Destroy(msg);
   }
   
   natsStatus setup_command_subscriber(natsSubscription **sub,
                                      natsConnection *conn,
                                      const char *device_id) {
       char subject[256];
       
       snprintf(subject, sizeof(subject), 
                "device.%s.cmd", device_id);
       
       return natsConnection_Subscribe(sub, conn, subject,
                                      command_handler, 
                                      (void*)device_id);
   }
   ```

### Phase 7: Build System

1. **CMake Configuration** (`CMakeLists.txt`)
   ```cmake
   cmake_minimum_required(VERSION 3.10)
   project(device_client C)
   
   set(CMAKE_C_STANDARD 11)
   set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -Wall -O2")
   
   # Find dependencies
   find_package(OpenSSL REQUIRED)
   find_package(Threads REQUIRED)
   find_package(PkgConfig REQUIRED)
   
   # Find nats.c
   pkg_check_modules(NATS REQUIRED nats)
   
   # Find json-c
   pkg_check_modules(JSON-C REQUIRED json-c)
   
   # Include directories
   include_directories(
       ${CMAKE_SOURCE_DIR}/include
       ${NATS_INCLUDE_DIRS}
       ${JSON-C_INCLUDE_DIRS}
       ${OPENSSL_INCLUDE_DIR}
   )
   
   # Source files
   set(SOURCES
       src/main.c
       src/nats_client.c
       src/tls_handler.c
       src/metrics.c
       src/commands.c
       src/config.c
   )
   
   # Create executable
   add_executable(device-client ${SOURCES})
   
   # Link libraries
   target_link_libraries(device-client
       ${NATS_LIBRARIES}
       ${JSON-C_LIBRARIES}
       ${OPENSSL_LIBRARIES}
       ${CMAKE_THREAD_LIBS_INIT}
       m
   )
   
   # Installation
   install(TARGETS device-client DESTINATION bin)
   ```

2. **Dockerfile** (`Dockerfile`)
   ```dockerfile
   FROM ubuntu:22.04 AS builder
   
   # Install build dependencies
   RUN apt-get update && apt-get install -y \
       build-essential \
       cmake \
       libssl-dev \
       libjson-c-dev \
       pkg-config \
       git \
       wget
   
   # Install nats.c
   RUN git clone https://github.com/nats-io/nats.c.git && \
       cd nats.c && \
       cmake . && \
       make && \
       make install
   
   # Copy source code
   WORKDIR /app
   COPY . .
   
   # Build application
   RUN mkdir build && \
       cd build && \
       cmake .. && \
       make
   
   # Runtime image
   FROM ubuntu:22.04
   
   RUN apt-get update && apt-get install -y \
       libssl3 \
       libjson-c5 \
       ca-certificates && \
       rm -rf /var/lib/apt/lists/*
   
   # Copy built application
   COPY --from=builder /app/build/device-client /usr/local/bin/
   COPY --from=builder /usr/local/lib/libnats* /usr/local/lib/
   
   # Update library cache
   RUN ldconfig
   
   # Create certificate directory
   RUN mkdir -p /etc/device-certs
   
   ENTRYPOINT ["device-client"]
   ```

### Phase 8: Testing Implementation

1. **Unit Tests** (`tests/test_metrics.c`)
   ```c
   #include <assert.h>
   #include <string.h>
   #include "metrics.h"
   
   void test_metrics_generation() {
       char buffer[1024];
       generate_metrics_json(buffer, sizeof(buffer), "test-001");
       
       // Check JSON structure
       assert(strstr(buffer, "\"device_id\": \"test-001\"") != NULL);
       assert(strstr(buffer, "\"temperature\":") != NULL);
       assert(strstr(buffer, "\"cpu_usage\":") != NULL);
       assert(strstr(buffer, "\"memory_mb\":") != NULL);
   }
   
   int main() {
       test_metrics_generation();
       printf("All tests passed!\n");
       return 0;
   }
   ```

### Phase 9: Deployment Scripts

1. **Device Launcher Script** (`scripts/launch-device.sh`)
   ```bash
   #!/bin/bash
   
   DEVICE_ID=$1
   LEAF_URL=${LEAF_URL:-"tls://leaf-nats.example.com:4222"}
   CERT_DIR=${CERT_DIR:-"/etc/device-certs"}
   
   if [ -z "$DEVICE_ID" ]; then
       echo "Usage: $0 <device-id>"
       exit 1
   fi
   
   # Check certificates exist
   if [ ! -f "$CERT_DIR/device-${DEVICE_ID}.crt" ]; then
       echo "Certificate not found for device ${DEVICE_ID}"
       exit 1
   fi
   
   # Launch device client
   exec device-client \
       --device-id "$DEVICE_ID" \
       --server "$LEAF_URL" \
       --cert "$CERT_DIR/device-${DEVICE_ID}.crt" \
       --key "$CERT_DIR/device-${DEVICE_ID}.key" \
       --ca "$CERT_DIR/ca.crt" \
       --interval "${METRICS_INTERVAL:-10}"
   ```

2. **Kubernetes Deployment** (`k8s/device-deployment.yaml`)
   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: simulated-devices
     namespace: devices
   spec:
     replicas: 10
     selector:
       matchLabels:
         app: device-client
     template:
       metadata:
         labels:
           app: device-client
       spec:
         containers:
         - name: device
           image: device-client:latest
           env:
           - name: DEVICE_ID
             valueFrom:
               fieldRef:
                 fieldPath: metadata.name
           - name: LEAF_URL
             value: "tls://nats-leaf-external:4222"
           volumeMounts:
           - name: certs
             mountPath: /etc/device-certs
             readOnly: true
         volumes:
         - name: certs
           secret:
             secretName: device-certificates
   ```

### Phase 10: Monitoring and Observability

1. **Metrics Export**
   ```c
   // Add Prometheus metrics export
   typedef struct {
       long messages_sent;
       long messages_received;
       long errors;
       time_t start_time;
   } device_stats_t;
   
   void export_prometheus_metrics(device_stats_t *stats) {
       printf("# HELP device_messages_sent_total Total messages sent\n");
       printf("# TYPE device_messages_sent_total counter\n");
       printf("device_messages_sent_total{device_id=\"%s\"} %ld\n",
              device_id, stats->messages_sent);
       
       printf("# HELP device_uptime_seconds Device uptime\n");
       printf("# TYPE device_uptime_seconds gauge\n");
       printf("device_uptime_seconds{device_id=\"%s\"} %ld\n",
              device_id, time(NULL) - stats->start_time);
   }
   ```

## Best Practices

1. **Security**
   - Protect private keys
   - Validate certificates
   - Use secure random for IDs
   - Implement rate limiting

2. **Reliability**
   - Handle reconnections gracefully
   - Buffer messages during disconnect
   - Implement exponential backoff
   - Add health checks

3. **Performance**
   - Use connection pooling
   - Batch metrics when possible
   - Optimize JSON generation
   - Monitor memory usage

## Testing Guide

1. **Local Testing**
   ```bash
   # Build the client
   mkdir build && cd build
   cmake ..
   make
   
   # Run with test certificates
   ./device-client \
     --device-id test-001 \
     --server tls://localhost:4222 \
     --cert ../tests/certs/device.crt \
     --key ../tests/certs/device.key \
     --ca ../tests/certs/ca.crt
   ```

2. **Integration Testing**
   - Test certificate validation
   - Verify metrics publishing
   - Test command processing
   - Validate reconnection logic

## Deployment Options

1. **Standalone Binary**: Direct execution on IoT devices
2. **Container**: Docker deployment for testing
3. **Kubernetes**: Simulated device fleet
4. **Embedded Systems**: Cross-compilation for ARM/MIPS