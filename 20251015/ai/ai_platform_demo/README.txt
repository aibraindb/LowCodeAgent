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
