#!/usr/bin/env bash
set -euo pipefail

BASE="/Volumes/Seagate/WellsFargo/LowCodeAgent/20251015"
DEMO="$BASE/ai_platform_demo"
DATA="$BASE/ai_platform_data"

echo "▶️  Preparing folders..."
mkdir -p "$DEMO" "$DATA"/{postgres,redis,arangodb,chroma,meili,kafka,zookeeper,langfuse,ollama,camunda/es,keycloak}
chmod -R 777 "$DATA"

############################################
# 1) Docker Compose (CPU-friendly + Kafka) #
############################################
cat > "$DEMO/docker-compose.yml" <<'YAML'
version: "3.9"
x-env: &env { TZ: UTC }
networks: { core: {}, camunda: {} }

services:
  postgres:
    image: postgis/postgis:16-3.4
    environment:
      <<: *env
      POSTGRES_USER: ${POSTGRES_USER:-ai}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD:-ai}
      POSTGRES_DB: ${POSTGRES_DB:-ai_platform}
    ports: ["5432:5432"]
    volumes:
      - /Volumes/Seagate/WellsFargo/LowCodeAgent/20251015/ai_platform_data/postgres:/var/lib/postgresql/data
    networks: [core]

  redis:
    image: redis:7.2
    command: ["redis-server","--save","","--appendonly","no"]
    ports: ["6379:6379"]
    volumes:
      - /Volumes/Seagate/WellsFargo/LowCodeAgent/20251015/ai_platform_data/redis:/data
    networks: [core]

  arangodb:
    image: arangodb:3.11
    environment:
      <<: *env
      ARANGO_ROOT_PASSWORD: ${ARANGO_ROOT_PASSWORD:-rootpwd}
    ports: ["8529:8529"]
    volumes:
      - /Volumes/Seagate/WellsFargo/LowCodeAgent/20251015/ai_platform_data/arangodb:/var/lib/arangodb3
    networks: [core]

  chroma:
    image: chromadb/chroma:latest
    environment:
      <<: *env
      IS_PERSISTENT: "TRUE"
      PERSIST_DIRECTORY: /chroma-data
    ports: ["8000:8000"]
    volumes:
      - /Volumes/Seagate/WellsFargo/LowCodeAgent/20251015/ai_platform_data/chroma:/chroma-data
    networks: [core]

  meilisearch:
    image: getmeili/meilisearch:v1.8
    environment: { MEILI_NO_ANALYTICS: "true" }
    ports: ["7700:7700"]
    volumes:
      - /Volumes/Seagate/WellsFargo/LowCodeAgent/20251015/ai_platform_data/meili:/meili_data
    networks: [core]

  # Confluent Kafka (reliable tags)
  zookeeper:
    image: confluentinc/cp-zookeeper:7.6.1
    environment:
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000
    ports: ["2181:2181"]
    volumes:
      - /Volumes/Seagate/WellsFargo/LowCodeAgent/20251015/ai_platform_data/zookeeper:/var/lib/zookeeper
    networks: [core]

  kafka:
    image: confluentinc/cp-kafka:7.6.1
    depends_on: [zookeeper]
    ports: ["9092:9092"]
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zookeeper:2181
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka:9092,PLAINTEXT_HOST://localhost:9092
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 1
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 1
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 1
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: "true"
      KAFKA_HEAP_OPTS: "-Xms256m -Xmx512m"
    volumes:
      - /Volumes/Seagate/WellsFargo/LowCodeAgent/20251015/ai_platform_data/kafka:/var/lib/kafka/data
    networks: [core]

  langfuse:
    image: ghcr.io/langfuse/langfuse:latest
    environment:
      DATABASE_URL: postgresql://${POSTGRES_USER:-ai}:${POSTGRES_PASSWORD:-ai}@postgres:5432/${POSTGRES_DB:-ai_platform}
      NEXTAUTH_URL: ${LANGFUSE_NEXTAUTH_URL:-http://localhost:3000}
      NEXTAUTH_SECRET: ${LANGFUSE_NEXTAUTH_SECRET:-devsecret}
      SALT: ${LANGFUSE_SALT:-langsalt}
      ENCRYPTION_KEY: ${LANGFUSE_ENCRYPTION_KEY:-00000000000000000000000000000000}
      TELEMETRY: "false"
      LANGFUSE_PUBLIC_KEY: ${LANGFUSE_PUBLIC_KEY:-public_dev}
      LANGFUSE_SECRET_KEY: ${LANGFUSE_SECRET_KEY:-secret_dev}
    depends_on: [postgres]
    ports: ["3000:3000"]
    networks: [core]

  # Spring Boot Orchestrator (Gradle build below)
  server:
    build:
      context: ./server
      dockerfile: Dockerfile
    environment:
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
    depends_on: [postgres, redis, kafka, arangodb, chroma, meilisearch, langfuse]
    networks: [core]

  # Node gateway for uploads + prompt assembly config
  nodeapi:
    image: node:20-alpine
    working_dir: /app
    command: sh -c "npm i && node index.js"
    environment:
      SPRING_BASE: http://server:8080
      CHROMA_URL: http://chroma:8000
      MEILI_URL: http://meilisearch:7700
      ARANGO_URL: http://arangodb:8529
      ARANGO_USER: root
      ARANGO_PASS: ${ARANGO_ROOT_PASSWORD:-rootpwd}
    ports: ["4000:4000"]
    volumes:
      - ./nodeapi:/app
      - /Volumes/Seagate/WellsFargo/LowCodeAgent/20251015/ai_platform_data:/data
    depends_on: [server]
    networks: [core]
YAML

#########################################
# 2) .env for Langfuse & DB credentials #
#########################################
cat > "$DEMO/.env" <<'ENV'
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

#####################################
# 3) Spring Boot (Gradle) skeleton  #
#####################################
mkdir -p "$DEMO/server/src/main/java/com/ai/server/controller" \
         "$DEMO/server/src/main/resources"
cat > "$DEMO/server/build.gradle" <<'GRADLE'
plugins {
  id 'java'
  id 'org.springframework.boot' version '3.3.0'
  id 'io.spring.dependency-management' version '1.1.5'
}
group='com.ai'; version='0.0.1-SNAPSHOT'; java { toolchain { languageVersion = JavaLanguageVersion.of(21) } }
repositories { mavenCentral() }
dependencies {
  implementation 'org.springframework.boot:spring-boot-starter-web'
  implementation 'org.springframework.boot:spring-boot-starter-data-jpa'
  implementation 'org.springframework.boot:spring-boot-starter-data-redis'
  implementation 'org.springframework.kafka:spring-kafka'
  runtimeOnly 'org.postgresql:postgresql'
  testImplementation 'org.springframework.boot:spring-boot-starter-test'
}
GRADLE

cat > "$DEMO/server/settings.gradle" <<'SET'
rootProject.name = 'ai-server'
SET

cat > "$DEMO/server/Dockerfile" <<'DOCKER'
FROM gradle:8.9-jdk21 AS build
WORKDIR /app
COPY . .
RUN gradle clean bootJar -x test --no-daemon
FROM eclipse-temurin:21-jre
WORKDIR /app
COPY --from=build /app/build/libs/*-SNAPSHOT.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java","-XX:+UseZGC","-Xms256m","-Xmx768m","-jar","/app/app.jar"]
DOCKER

cat > "$DEMO/server/src/main/resources/application-docker.yml" <<'YML'
server.port: 8080
spring:
  datasource:
    url: ${DB_URL}
    username: ${DB_USER}
    password: ${DB_PASS}
  jpa:
    hibernate.ddl-auto: none
  redis:
    url: ${REDIS_URL}
  kafka:
    bootstrap-servers: ${KAFKA_BOOTSTRAP}
YML

cat > "$DEMO/server/src/main/java/com/ai/server/DemoApplication.java" <<'JAVA'
package com.ai.server;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
@SpringBootApplication
public class DemoApplication {
  public static void main(String[] args){ SpringApplication.run(DemoApplication.class, args); }
}
JAVA

# Health + minimal prompt assembly endpoint
cat > "$DEMO/server/src/main/java/com/ai/server/controller/ApiController.java" <<'JAVA'
package com.ai.server.controller;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import java.util.*;

@RestController
@RequestMapping("/api")
public class ApiController {

  @GetMapping("/health")
  public Map<String,String> health(){ return Map.of("status","UP","version","0.0.1"); }

  // Minimal "configurable prompt assembly" stub
  @PostMapping("/assemble")
  public ResponseEntity<Map<String,Object>> assemble(@RequestBody Map<String,Object> cfg){
    Map<String,Object> res = new HashMap<>();
    res.put("promptId", UUID.randomUUID().toString());
    res.put("model", cfg.getOrDefault("model","mistral:tiny"));
    res.put("fiboTags", cfg.getOrDefault("fiboTags", List.of("Loan","Rate","Borrower")));
    res.put("template", "You are a document QA engine. Use provided context and answer strictly in JSON.");
    res.put("assembledAt", new Date().toString());
    return ResponseEntity.ok(res);
  }
}
JAVA

#####################################
# 4) Node API (uploads + assembly)  #
#####################################
mkdir -p "$DEMO/nodeapi"
cat > "$DEMO/nodeapi/package.json" <<'PKG'
{
  "name": "node-gateway",
  "version": "0.1.0",
  "type": "module",
  "dependencies": {
    "axios": "^1.6.7",
    "express": "^4.19.2",
    "multer": "^1.4.5-lts.1"
  }
}
PKG

cat > "$DEMO/nodeapi/index.js" <<'JS'
import express from "express";
import multer from "multer";
import axios from "axios";
const app = express();
const upload = multer({ dest: "/data/uploads" });
app.use(express.json());

const SPRING_BASE = process.env.SPRING_BASE || "http://server:8080";

// health
app.get("/health", (_, res) => res.json({ status:"UP", service:"nodeapi" }));

// upload document (excel/word/pdf/ppt/html) — just stores and echoes path
app.post("/upload", upload.single("file"), async (req, res) => {
  const { originalname, path } = req.file || {};
  res.json({ ok:true, name: originalname, path });
});

// build prompt (configurable)
app.post("/prompt/assemble", async (req, res) => {
  try {
    const { data } = await axios.post(`${SPRING_BASE}/api/assemble`, req.body, { timeout: 60000 });
    res.json(data);
  } catch (e) {
    res.status(500).json({ error: e.message });
  }
});

app.listen(4000, () => console.log("Node API listening on 4000"));
JS

#####################################
# 5) Build & start the whole stack  #
#####################################
echo "🧱 Building Spring Boot..."
docker run --rm -v "$DEMO/server":/app -w /app gradle:8.9-jdk21 \
  gradle clean bootJar -x test --no-daemon

echo "🐳 Bringing containers up..."
cd "$DEMO"
docker compose down -v --remove-orphans || true
docker compose up -d

echo ""
echo "✅ Up! URLs:"
echo "Spring Boot:     http://localhost:8080/api/health"
echo "Node API:        http://localhost:4000/health"
echo "Langfuse:        http://localhost:3000"
echo "ArangoDB:        http://localhost:8529  (user: root / pass: rootpwd)"
echo "Chroma:          http://localhost:8000"
echo "Meilisearch:     http://localhost:7700"
echo "Kafka:           localhost:9092"
echo "Redis:           localhost:6379"
echo "Postgres:        localhost:5432 (ai/ai)"
echo ""
echo "➡️  Try:"
echo "curl http://localhost:4000/health"
echo "curl -X POST http://localhost:4000/prompt/assemble -H 'Content-Type: application/json' -d '{\"model\":\"gpt-4o\",\"fiboTags\":[\"Loan\",\"APR\"],\"docType\":\"ClosingDisclosure\"}'"
echo "curl -F file=@/etc/hosts http://localhost:4000/upload"
