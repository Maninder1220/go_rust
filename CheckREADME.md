# OSAI Agent

OSAI Agent is a **Rust-first local Linux and DevOps intelligence agent**. It scans the machine, stores exact facts, archives raw evidence, prepares AI memory, and can ask a local llama.cpp/Qwen model using recalled Cognee context.

The current project is intentionally split into Rust binaries plus Docker services:

```text
Rust binaries:
  osai-agent             = scanner + dashboard + API + guarded actions
  osai-storage-worker    = PostgreSQL + RustFS persistence worker
  osai-cognee-ingest     = pushes pending memory rows into Cognee REST
  osai-ask               = recalls Cognee memory + asks llama.cpp/Qwen

Docker Compose services:
  postgres               = operational DB + Cognee DB + pgvector
  rustfs                 = S3-compatible raw evidence store
  rustfs-init            = creates the osai-agent bucket once
  cognee                 = Cognee REST API memory/retrieval server

Host service:
  llama.cpp llama-server = local inference using Qwen3-4B-Q4_K_M.gguf
```

## Mental model

```text
Rust scans and controls.
PostgreSQL stores exact facts and metadata.
RustFS stores raw JSON/log/report objects.
Cognee stores searchable AI memory.
pgvector finds semantically similar memory.
Kuzu stores relationships/graph memory.
llama.cpp runs Qwen locally.
Rust sends Qwen only the useful retrieved context.
```

Qwen does **not** directly read PostgreSQL, RustFS, pgvector, or Kuzu. Rust fetches facts and memory first, builds a safe prompt, sends that prompt to llama.cpp/Qwen, and then can save the answer back.

## What the project can do now

- Serve a browser dashboard from the Rust binary.
- Expose API endpoints for health, snapshot, history, knowledge, plugins, reasoning, and guarded actions.
- Scan Linux host state: OS, CPU, memory, disk, processes, ports, Kubernetes signals, and GitLab signals.
- Apply rule findings for high memory, high CPU, disk pressure, sensitive ports, Kubernetes detection, GitLab detection, and known GitLab auto-start memory pattern.
- Keep local JSONL scan history in `data/scan_history.jsonl`.
- Persist structured scan metadata to PostgreSQL.
- Persist full raw scan JSON to RustFS.
- Create compact memory rows in PostgreSQL.
- Push pending memory rows to Cognee over REST.
- Ask local Qwen via llama.cpp using PostgreSQL facts plus recalled Cognee memory.

## Project structure

```text
osai-agent/
├── Cargo.toml
├── Cargo.lock
├── README.md
├── docker-compose.storage.yml
├── .env.storage.example
├── .env.cognee.example
├── config/
│   └── osai-agent.toml
├── docker/
│   └── cognee/
│       └── Dockerfile
├── docs/
│   ├── llama-qwen-cognee-rust-architecture.md
│   ├── phase3-storage-cognee.md
│   ├── rust-storage-worker.md
│   ├── rust-to-cognee-to-qwen-data-flow.md
│   └── understanding-model-metadata-like-a-pro.md
├── knowledge/
│   └── *.md
├── packaging/
│   ├── rpm/
│   └── systemd/
├── scripts/
│   ├── ask-local-qwen.sh
│   ├── build-rpm.sh
│   ├── run-cognee-ingest.sh
│   ├── run-memory-worker.sh
│   └── setup-storage-venv.sh  # deprecated; use Docker Compose for Cognee
├── src/
│   ├── main.rs
│   ├── actions.rs
│   ├── history.rs
│   ├── knowledge.rs
│   ├── reasoning.rs
│   ├── rules.rs
│   ├── bin/
│   │   ├── osai-storage-worker.rs
│   │   ├── osai-cognee-ingest.rs
│   │   └── osai-ask.rs
│   ├── collector/
│   └── plugins/
├── storage/
│   ├── postgres-init/
│   └── migrations/
└── web/
    ├── index.html
    ├── app.css
    └── app.js
```

## Service dependency flow

Start in this order:

```text
1. PostgreSQL + RustFS + Cognee container stack
2. llama.cpp/Qwen server
3. osai-agent Rust server
4. osai-storage-worker
5. osai-cognee-ingest
6. osai-ask
```

Dependency map:

```text
osai-agent
  depends on: no external service for basic dashboard/scanning

osai-storage-worker
  depends on: osai-agent API, PostgreSQL, RustFS bucket

osai-cognee-ingest
  depends on: PostgreSQL, Cognee REST API

osai-ask
  depends on: PostgreSQL, Cognee REST API, llama.cpp/Qwen

cognee container
  depends on: PostgreSQL, llama.cpp endpoint for ingestion/extraction quality
```

## 1. Prepare environment files

```bash
cp .env.storage.example .env.storage
cp .env.cognee.example .env.cognee
```

Important config files:

```text
.env.storage = Rust worker config for osai-agent API, PostgreSQL, RustFS, dataset names
.env.cognee  = Cognee container config plus local llama.cpp/Qwen config
```

## 2. Start Docker Compose services

```bash
docker compose -f docker-compose.storage.yml up -d --build
```

This starts:

```text
osai-postgres    PostgreSQL + pgvector
osai-rustfs      RustFS object store
osai-rustfs-init one-shot bucket bootstrap for s3://osai-agent
osai-cognee      Cognee REST API on port 8001
```

Check status:

```bash
docker compose -f docker-compose.storage.yml ps
```

Check logs:

```bash
docker logs osai-postgres --tail 50
docker logs osai-rustfs --tail 50
docker logs osai-cognee --tail 50
```

Open RustFS console:

```text
http://127.0.0.1:9001
username: rustfsadmin
password: rustfsadmin
```

Open Cognee docs:

```text
http://127.0.0.1:8001/docs
```

## 3. Start llama.cpp with Qwen3

Start Qwen on the host, not inside this compose file:

```bash
./llama-server \
  -m /path/to/Qwen3-4B-Q4_K_M.gguf \
  --host 127.0.0.1 \
  --port 8080 \
  --alias osai-llm \
  -c 4096
```

Test it:

```bash
curl http://127.0.0.1:8080/v1/models
```

Why the endpoints differ:

```text
Rust host binaries call llama.cpp at:
  http://127.0.0.1:8080/v1

Cognee container calls the host llama.cpp through Docker host gateway:
  http://host.docker.internal:8080/v1
```

## 4. Build Rust binaries

```bash
cargo check
cargo build --release
```

Release binaries:

```text
target/release/osai-agent
target/release/osai-storage-worker
target/release/osai-cognee-ingest
target/release/osai-ask
```

## 5. Start the Rust agent

```bash
./target/release/osai-agent --bind 127.0.0.1:8000 --scan-interval-seconds 30
```

Open dashboard:

```text
http://127.0.0.1:8000
```

Basic API checks:

```bash
curl http://127.0.0.1:8000/api/health
curl http://127.0.0.1:8000/api/snapshot | jq
curl http://127.0.0.1:8000/api/history | jq
```

## 6. Persist scan data into PostgreSQL and RustFS

Run once:

```bash
./target/release/osai-storage-worker --once
```

Or use the wrapper:

```bash
./scripts/run-memory-worker.sh --once
```

Run continuously:

```bash
./target/release/osai-storage-worker
```

This writes:

```text
PostgreSQL:
  osai_hosts
  osai_scan_history
  osai_findings
  osai_memory_events
  osai_cognee_outbox

RustFS:
  s3://osai-agent/snapshots/<hostname>/<generated-at>/<scan-id>.json
```

## 7. Verify PostgreSQL data

```bash
docker exec -it osai-postgres psql -U postgres -d osai_agent -c '\dt'
```

Latest scans:

```bash
docker exec -it osai-postgres psql -U postgres -d osai_agent -c "
select id, generated_at, hostname, highest_severity, finding_count, object_store_key
from osai_scan_history
order by generated_at desc
limit 5;
"
```

Memory/outbox:

```bash
docker exec -it osai-postgres psql -U postgres -d osai_agent -c "
select id, scan_id, status, attempt_count, last_error, ingested_at
from osai_cognee_outbox
order by id desc
limit 10;
"
```

pgvector extension in Cognee DB:

```bash
docker exec -it osai-postgres psql -U postgres -d cognee_db -c "
select extname, extversion from pg_extension where extname = 'vector';
"
```

## 8. Verify RustFS data from CLI

Using AWS CLI:

```bash
export AWS_ACCESS_KEY_ID=rustfsadmin
export AWS_SECRET_ACCESS_KEY=rustfsadmin
export AWS_DEFAULT_REGION=us-east-1
export AWS_EC2_METADATA_DISABLED=true

aws --endpoint-url http://127.0.0.1:9000 s3 ls
aws --endpoint-url http://127.0.0.1:9000 s3 ls s3://osai-agent/ --recursive
```

Read one object:

```bash
aws --endpoint-url http://127.0.0.1:9000 s3 cp \
  s3://osai-agent/<object_store_key_from_postgres> - | jq .
```

## 9. Ingest pending memory into Cognee

Run once:

```bash
./target/release/osai-cognee-ingest --once
```

Or use the wrapper:

```bash
./scripts/run-cognee-ingest.sh --once
```

Expected outbox status:

```text
ingested
```

Check:

```bash
docker exec -it osai-postgres psql -U postgres -d osai_agent -c "
select id, scan_id, status, attempt_count, last_error, ingested_at
from osai_cognee_outbox
order by id desc
limit 10;
"
```

If it fails, check:

```bash
docker logs osai-cognee --tail 100
```

## 10. Ask Qwen using Cognee memory

```bash
./target/release/osai-ask "give me update about this server"
```

Or:

```bash
./scripts/ask-local-qwen.sh "give me update about this server"
```

Request path:

```text
osai-ask
  -> PostgreSQL latest scan facts
  -> Cognee /api/v1/recall
  -> llama.cpp /v1/chat/completions
  -> Qwen answer printed in CLI
```

## Browser, CLI, and API access

Browser dashboard:

```text
http://127.0.0.1:8000
```

RustFS console:

```text
http://127.0.0.1:9001
```

Cognee REST docs:

```text
http://127.0.0.1:8001/docs
```

CLI examples:

```bash
./target/release/osai-storage-worker --once
./target/release/osai-cognee-ingest --once
./target/release/osai-ask "what changed on this machine?"
```

API examples:

```bash
curl http://127.0.0.1:8000/api/health
curl http://127.0.0.1:8000/api/snapshot | jq
curl http://127.0.0.1:8000/api/history | jq
curl -X POST http://127.0.0.1:8000/api/scan | jq
```

## Expose dashboard outside localhost safely

When binding to `0.0.0.0`, set an API token:

```bash
export OSAI_AGENT_TOKEN='change-me-long-random-token'
./target/release/osai-agent --bind 0.0.0.0:8000
```

API call with token:

```bash
curl -H "X-OSAI-Token: $OSAI_AGENT_TOKEN" http://127.0.0.1:8000/api/snapshot | jq
```

## Guarded command executor

The executor validates commands against an allowlist, blocks destructive programs, rejects shell metacharacters, audits actions, and requires approval for repair actions.

Propose a read-only check:

```bash
curl -X POST http://127.0.0.1:8000/api/actions/propose \
  -H 'Content-Type: application/json' \
  -d '{
    "reason":"check GitLab status",
    "command":"gitlab-ctl",
    "args":["status"],
    "kind":"read_only"
  }' | jq
```

Run the returned action id:

```bash
curl -X POST http://127.0.0.1:8000/api/actions/<action-id>/run | jq
```

## Important design rules

Do not use Cognee as the only database for system state.

```text
PostgreSQL = operational source of truth
RustFS     = raw evidence vault
Cognee     = AI memory/retrieval layer
Qwen       = reasoning model, not storage
Rust       = controller and guardrail layer
```

Do not send raw RustFS logs directly into Qwen by default. Let Rust curate facts, let Cognee recall relevant memory, and send Qwen a clean prompt.

## Cleaning heavy folders

These folders are generated and should not be committed:

```text
target/
.venv-storage/
data/
```

Clean Rust build cache:

```bash
cargo clean
```

Remove old Python venv if it exists:

```bash
rm -rf .venv-storage scripts/.venv-storage
```

## RPM/systemd packaging

Systemd and RPM skeletons remain under:

```text
packaging/systemd/
packaging/rpm/
```

Build RPM on a RHEL-like host:

```bash
sudo dnf install -y rust cargo rpm-build rsync systemd-rpm-macros
./scripts/build-rpm.sh
```

## References

- Cognee REST API server: https://docs.cognee.ai/guides/deploy-rest-api-server
- Cognee installation and extras: https://docs.cognee.ai/getting-started/installation
- Cognee LLM providers: https://docs.cognee.ai/setup-configuration/llm-providers
- RustFS Docker installation: https://docs.rustfs.com/installation/docker/
- Docker Compose services: https://docs.docker.com/reference/compose-file/services/
- Full OSAI data flow: `docs/rust-to-cognee-to-qwen-data-flow.md`
