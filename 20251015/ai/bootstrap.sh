#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(pwd)/ai_platform_demo"
COMPOSE_FILE="$ROOT_DIR/docker-compose.yml"
ENV_FILE="$ROOT_DIR/.env"
SERVER_DIR="$ROOT_DIR/server"

echo "Preparing demo directory: $ROOT_DIR"
rm -rf "$ROOT_DIR"
mkdir -p "$ROOT_DIR"
mkdir -p "$SERVER_DIR/src/main/java/com/example/demo"
mkdir -p "$SERVER_DIR/src/main/resources"
mkdir -p "$SERVER_DIR/src/main/java/com/example/demo/controller"

# -----------------------
# 1) Write docker-compose.yml
# -----------------------
cat > "$COMPOSE_FILE" <<'YAML'
version: "3.9"

x-env: &env
  TZ: UTC

networks:
  core:
  camunda:

volumes:
  pgdata:
  redisdata:
  arangodata:
  chromadata:
  meili-data:
  langfuse-data:
  kafka-data:
  zookeeper-data:
  esdata:
  keycloak-data:
  ollama:

services:

  postgres:
    image: postgis/postgis:16-3.4
    container_name: postgres
    environment:
      <<: *env
      POSTGRES_USER: ${POSTGRES_USER:-ai}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-ai}
      POSTGRES_DB: ${POSTGRES_DB:-ai_platform}
      POSTGRES_INITDB_ARGS: "--data-checksums"
    healthcheck:
      test: ["CMD-SHELL","pg_isready -U ${POSTGRES_USER:-ai} -d ${POSTGRES_DB:-ai_platform}"]
      interval: 10s
      timeout: 5s
      retries: 10
    ports: ["5432:5432"]
    volumes:
      - pgdata:/var/lib/postgresql/data
    networks: [core]

  redis:
    image: redis:7.2
    container_name: redis
    command: ["redis-server","--save","","--appendonly","no"]
    ports: ["6379:6379"]
    volumes:
      - redisdata:/data
    networks: [core]

  arangodb:
    image: arangodb:3.11
    container_name: arangodb
    environment:
      <<: *env
      ARANGO_ROOT_PASSWORD: ${ARANGO_ROOT_PASSWORD:-rootpwd}
    ports: ["8529:8529"]
    volumes:
      - arangodata:/var/lib/arangodb3
    networks: [core]

  chroma:
    image: chromadb/chroma:latest
    container_name: chroma
    environment:
      <<: *env
      IS_PERSISTENT: "TRUE"
      PERSIST_DIRECTORY: /chroma-data
    ports: ["8000:8000"]
    volumes:
      - chromadata:/chroma-data
    networks: [core]

  meilisearch:
    image: getmeili/meilisearch:v1.8
    container_name: meilisearch
    environment:
      <<: *env
      MEILI_NO_ANALYTICS: "true"
    ports: ["7700:7700"]
    volumes:
      - meili-data:/meili_data
    networks: [core]

  zookeeper:
    image: bitnami/zookeeper:3.9
    container_name: zookeeper
    environment:
      <<: *env
      ALLOW_ANONYMOUS_LOGIN: "yes"
    ports: ["2181:2181"]
    volumes:
      - zookeeper-data:/bitnami/zookeeper
    networks: [core]

  kafka:
    image: bitnami/kafka:3.7
    container_name: kafka
    environment:
      <<: *env
      KAFKA_CFG_NODE_ID: 0
      KAFKA_CFG_PROCESS_ROLES: controller,broker
      KAFKA_CFG_CONTROLLER_QUORUM_VOTERS: "0@kafka:9093"
      KAFKA_CFG_LISTENERS: "PLAINTEXT://:9092,CONTROLLER://:9093"
      KAFKA_CFG_ADVERTISED_LISTENERS: "PLAINTEXT://kafka:9092"
      KAFKA_CFG_CONTROLLER_LISTENER_NAMES: CONTROLLER
      KAFKA_CFG_LISTENER_SECURITY_PROTOCOL_MAP: "CONTROLLER:PLAINTEXT,PLAINTEXT:PLAINTEXT"
      KAFKA_CFG_AUTO_CREATE_TOPICS_ENABLE: "true"
      KAFKA_HEAP_OPTS: "-Xms256m -Xmx512m"
    depends_on:
      - zookeeper
    ports: ["9092:9092"]
    volumes:
      - kafka-data:/bitnami/kafka
    networks: [core]

  langfuse:
    image: ghcr.io/langfuse/langfuse:latest
    container_name: langfuse
    environment:
      <<: *env
      DATABASE_URL: postgresql://${POSTGRES_USER:-ai}:${POSTGRES_PASSWORD:-ai}@postgres:5432/${POSTGRES_DB:-ai_platform}
      NEXTAUTH_URL: ${LANGFUSE_NEXTAUTH_URL:-http://localhost:3000}
      NEXTAUTH_SECRET: ${LANGFUSE_NEXTAUTH_SECRET:-devsecret}
      SALT: ${LANGFUSE_SALT:-langsalt}
      ENCRYPTION_KEY: ${LANGFUSE_ENCRYPTION_KEY:-00000000000000000000000000000000}
      TELEMETRY: "false"
      LANGFUSE_PUBLIC_KEY: ${LANGFUSE_PUBLIC_KEY:-public_dev}
      LANGFUSE_SECRET_KEY: ${LANGFUSE_SECRET_KEY:-secret_dev}
    depends_on:
      - postgres
    ports: ["3000:3000"]
    networks: [core]

  server:
    build:
      context: ./server
      dockerfile: Dockerfile
    container_name: ai-server
    environment:
      <<: *env
      SPRING_PROFILES_ACTIVE: docker
      DB_URL: jdbc:postgresql://postgres:5432/${POSTGRES_DB:-ai_platform}
      DB_USER: ${POSTGRES_USER:-ai}
      DB_PASS: ${POSTGRES_PASSWORD:-ai}
      REDIS_URL: redis://redis:6379
      KAFKA_BOOTSTRAP: kafka:9092
      ARANGO_URL: http://arangodb:8529
      ARANGO_USER: root
      ARANGO_PASS: ${ARANGO_ROOT_PASSWORD:-rootpwd}
      CHROMA_URL: http://chroma:8000
      MEILI_URL: http://meilisearch:7700
      LANGFUSE_BASEURL: http://langfuse:3000
      LANGFUSE_PUBLIC_KEY: ${LANGFUSE_PUBLIC_KEY:-public_dev}
      LANGFUSE_SECRET_KEY: ${LANGFUSE_SECRET_KEY:-secret_dev}
    ports: ["8080:8080"]
    depends_on:
      - postgres
      - redis
      - kafka
      - arangodb
      - chroma
      - meilisearch
      - langfuse
    networks: [core]

  ollama:
    profiles: ["llm"]
    image: ollama/ollama:latest
    container_name: ollama
    restart: unless-stopped
    volumes:
      - ollama:/root/.ollama
    ports:
      - "11434:11434"
    networks: [core]

  # Camunda profile (enable with --profile camunda)
  elasticsearch:
    profiles: ["camunda"]
    image: docker.elastic.co/elasticsearch/elasticsearch:8.13.4
    container_name: camunda-es
    environment:
      <<: *env
      discovery.type: single-node
      xpack.security.enabled: "false"
      ES_JAVA_OPTS: "-Xms512m -Xmx512m"
    ulimits:
      memlock: { soft: -1, hard: -1 }
      nofile: { soft: 65536, hard: 65536 }
    volumes:
      - esdata:/usr/share/elasticsearch/data
    networks: [camunda]

  zeebe:
    profiles: ["camunda"]
    image: camunda/zeebe:8.6.3
    container_name: zeebe
    environment:
      <<: *env
      ZEEBE_BROKER_GATEWAY_NETWORK_HOST: 0.0.0.0
    ports: ["26500:26500"]
    depends_on: [elasticsearch]
    networks: [camunda]

  operate:
    profiles: ["camunda"]
    image: camunda/operate:8.6.3
    container_name: operate
    environment:
      <<: *env
      CAMUNDA_OPERATE_ELASTICSEARCH_URL: http://elasticsearch:9200
      CAMUNDA_OPERATE_ZEEBE_GATEWAYADDRESS: zeebe:26500
    ports: ["8081:8080"]
    depends_on: [zeebe, elasticsearch]
    networks: [camunda]

  tasklist:
    profiles: ["camunda"]
    image: camunda/tasklist:8.6.3
    container_name: tasklist
    environment:
      <<: *env
      CAMUNDA_TASKLIST_ELASTICSEARCH_URL: http://elasticsearch:9200
      CAMUNDA_TASKLIST_ZEEBE_GATEWAYADDRESS: zeebe:26500
    ports: ["8082:8080"]
    depends_on: [zeebe, elasticsearch]
    networks: [camunda]

  keycloak:
    profiles: ["camunda"]
    image: quay.io/keycloak/keycloak:24.0.5
    container_name: keycloak
    command: ["start-dev","--http-port=8080"]
    environment:
      <<: *env
      KEYCLOAK_ADMIN: admin
      KEYCLOAK_ADMIN_PASSWORD: admin
    ports: ["8090:8080"]
    volumes:
      - keycloak-data:/opt/keycloak/data
    networks: [camunda]

volumes:
  pgdata:
  redisdata:
  arangodata:
  chromadata:
  meili-data:
  langfuse-data:
  kafka-data:
  zookeeper-data:
  esdata:
  keycloak-data:
  ollama:
YAML

# -----------------------
# 2) Write a minimal .env
# -----------------------
cat > "$ENV_FILE" <<'ENV'
POSTGRES_USER=ai
POSTGRES_PASSWORD=ai
POSTGRES_DB=ai_platform
ARANGO_ROOT_PASSWORD=rootpwd

LANGFUSE_NEXTAUTH_URL=http://localhost:3000
LANGFUSE_NEXTAUTH_SECRET=devsecret
LANGFUSE_SALT=langsalt
LANGFUSE_ENCRYPTION_KEY=00000000000000000000000000000000
LANGFUSE_PUBLIC_KEY=public_dev
LANGFUSE_SECRET_KEY=secret_dev
ENV

# -----------------------
# 3) Scaffold minimal Spring Boot (Gradle) app
#    - Basic health endpoint and /cases simple CRUD using an in-memory map + Postgres wiring stub
# -----------------------
cat > "$SERVER_DIR/build.gradle" <<'GRADLE'
plugins {
    id 'java'
    id 'org.springframework.boot' version '3.3.0'
    id 'io.spring.dependency-management' version '1.1.5'
}

group = 'com.example'
version = '0.0.1-SNAPSHOT'
sourceCompatibility = '21'

repositories { mavenCentral() }

dependencies {
    implementation 'org.springframework.boot:spring-boot-starter-web'
    implementation 'org.springframework.kafka:spring-kafka'
    implementation 'org.springframework.boot:spring-boot-starter-data-jpa'
    implementation 'org.springframework.boot:spring-boot-starter-data-redis'
    runtimeOnly 'org.postgresql:postgresql'
    testImplementation 'org.springframework.boot:spring-boot-starter-test'
}

tasks.withType(JavaCompile) {
    options.encoding = 'UTF-8'
}
GRADLE

cat > "$SERVER_DIR/settings.gradle" <<'SETTINGS'
rootProject.name = 'ai-server'
SETTINGS

cat > "$SERVER_DIR/Dockerfile" <<'DOCKERFILE'
FROM gradle:8.9-jdk21 AS build
WORKDIR /app
COPY . .
RUN gradle clean bootJar -x test --no-daemon

FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /app/build/libs/*-SNAPSHOT.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java","-XX:+UseZGC","-Xms256m","-Xmx768m","-jar","/app/app.jar"]
DOCKERFILE

cat > "$SERVER_DIR/src/main/java/com/example/demo/DemoApplication.java" <<'JAVA'
package com.example.demo;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
@SpringBootApplication
public class DemoApplication {
  public static void main(String[] args) {
    SpringApplication.run(DemoApplication.class, args);
  }
}
JAVA

cat > "$SERVER_DIR/src/main/java/com/example/demo/controller/HealthController.java" <<'JAVA'
package com.example.demo.controller;

import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;
import java.util.Map;

@RestController
public class HealthController {
    @GetMapping("/api/health")
    public Map<String, String> health() {
        return Map.of("status", "UP", "version", "0.0.1");
    }
}
JAVA

cat > "$SERVER_DIR/src/main/java/com/example/demo/controller/CaseController.java" <<'JAVA'
package com.example.demo.controller;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import java.util.*;
import java.util.concurrent.ConcurrentHashMap;

@RestController
@RequestMapping("/api/cases")
public class CaseController {
    private final Map<String, Map<String,Object>> store = new ConcurrentHashMap<>();

    @PostMapping
    public ResponseEntity<Map<String,Object>> createCase(@RequestBody Map<String,Object> req) {
        String id = UUID.randomUUID().toString();
        Map<String,Object> rec = new HashMap<>(req);
        rec.put("caseId", id);
        rec.put("status", "RECEIVED");
        rec.put("createdAt", new Date().toString());
        store.put(id, rec);
        return ResponseEntity.ok(rec);
    }

    @GetMapping("/{id}")
    public ResponseEntity<Object> getCase(@PathVariable String id) {
        if(!store.containsKey(id)) return ResponseEntity.notFound().build();
        return ResponseEntity.ok(store.get(id));
    }

    @GetMapping
    public ResponseEntity<List<Map<String,Object>>> listCases() {
        return ResponseEntity.ok(new ArrayList<>(store.values()));
    }
}
JAVA

cat > "$SERVER_DIR/src/main/resources/application-docker.yml" <<'APPYML'
server:
  port: 8080

spring:
  datasource:
    url: ${DB_URL:jdbc:postgresql://postgres:5432/ai_platform}
    username: ${DB_USER:ai}
    password: ${DB_PASS:ai}
  jpa:
    hibernate:
      ddl-auto: none
    properties:
      hibernate:
        jdbc:
          time_zone: UTC

ai:
  arango:
    url: ${ARANGO_URL:http://arangodb:8529}
    user: ${ARANGO_USER:root}
    pass: ${ARANGO_PASS:rootpwd}
APPYML

# -----------------------
# 4) Make docker-compose run script
# -----------------------
RUN_SCRIPT="$ROOT_DIR/run_compose.sh"
cat > "$RUN_SCRIPT" <<'RUN'
#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
export COMPOSE_HTTP_TIMEOUT=300
cd "$HERE"
echo "Starting core stack (no camunda, no llm profile)..."
docker compose up -d
echo "You can enable Camunda with: docker compose --profile camunda up -d"
echo "You can enable local Ollama LLM with: docker compose --profile llm up -d"
echo "Waiting for services to stabilize (sleeping 20s)..."
sleep 20
echo "Services started. Useful URLs:"
echo "  Spring service: http://localhost:8080/api/health"
echo "  Postgres: localhost:5432 (user: ai / password: ai)"
echo "  Redis: localhost:6379"
echo "  Kafka bootstrap: localhost:9092"
echo "  ArangoDB web: http://localhost:8529  (user: root / password from .env)"
echo "  Chroma vector DB: http://localhost:8000"
echo "  Meilisearch: http://localhost:7700"
echo "  Langfuse: http://localhost:3000 (may take time to initialize)"
echo ""
echo "To view logs: docker compose logs -f server"
RUN

chmod +x "$RUN_SCRIPT"

# -----------------------
# 5) Final instructions & run
# -----------------------
cat > "$ROOT_DIR/README.txt" <<'README'
AI Platform Demo
----------------
1) Edit .env to change credentials if desired.
2) Run the stack:
   cd ai_platform_demo
   ./run_compose.sh

3) After stack is up:
   - Health: http://localhost:8080/api/health
   - Create case: POST http://localhost:8080/api/cases  with JSON body {"name":"Test"}
   - Arango UI: http://localhost:8529  (user: root, password in .env)
   - Langfuse UI: http://localhost:3000

Notes:
- To bring up Camunda (Zeebe/Operate/Tasklist/Keycloak), re-run:
  docker compose --profile camunda up -d
- To enable local Ollama LLM: docker compose --profile llm up -d
README

chmod +x "$ROOT_DIR/run_compose.sh"

echo "Bootstrap generated in: $ROOT_DIR"
echo "1) Inspect/modify .env at: $ENV_FILE"
echo "2) Start stack: cd $ROOT_DIR && ./run_compose.sh"
echo ""
echo "Now starting the compose process..."
cd "$ROOT_DIR"
./run_compose.sh

echo "Finished. Wait a minute for DBs and services to finish initializing, then visit the URLs shown above."
