# OSAI Agent

OSAI Agent is a Rust-first local machine intelligence agent for Linux hosts.

This version upgrades the Phase 1 read-only scanner into a Rust-first local agent with durable storage:

- persistent scan history
- rule engine
- local reasoning over Markdown knowledge files
- guarded command executor
- approval workflow before repair actions
- Kubernetes plugin
- GitLab plugin
- Rust storage worker binary
- PostgreSQL operational storage
- RustFS S3-compatible raw evidence storage
- Cognee-ready memory outbox
- optional llama.cpp/Qwen local inference path
- systemd service template
- RPM packaging skeleton for RHEL/CentOS
- dashboard/API token protection before exposing outside localhost

## Current safety model

The agent still starts from observation first.

It can collect machine state and suggest safe checks. It does **not** run raw shell strings. The executor accepts only a program name plus argument array, validates commands against an allowlist, blocks destructive programs, rejects shell metacharacters, audits actions, and requires approval for repair actions.

## Run locally

```bash
cd osai-agent
cargo run -- --bind 127.0.0.1:8000 --scan-interval-seconds 20
```

Open:

```text
http://127.0.0.1:8000
```

## Build binary

```bash
cargo build --release
./target/release/osai-agent --bind 127.0.0.1:8000
```

## Expose outside localhost safely

When you bind to `0.0.0.0`, the agent refuses to start unless you set an API token or explicitly allow insecure public mode.

Recommended:

```bash
export OSAI_AGENT_TOKEN='change-me-long-random-token'
./target/release/osai-agent --bind 0.0.0.0:8000
```

Then the dashboard prompts for the token. API calls can also pass:

```bash
curl -H "X-OSAI-Token: $OSAI_AGENT_TOKEN" http://127.0.0.1:8000/api/snapshot | jq
```

Only use this for a lab:

```bash
./target/release/osai-agent --bind 0.0.0.0:8000 --allow-insecure-public-dashboard
```

## Persistent scan history

By default, history is stored in:

```text
data/scan_history.jsonl
```

Change location:

```bash
./target/release/osai-agent --data-dir /var/lib/osai-agent
```

Useful APIs:

```bash
curl http://127.0.0.1:8000/api/history | jq
curl http://127.0.0.1:8000/api/history/<history-id> | jq
```

Each line in `scan_history.jsonl` contains the complete snapshot plus summary fields.

## Rule engine

Rules live in:

```text
src/rules.rs
```

Current rule categories:

- Linux memory pressure
- Linux CPU pressure
- Linux disk usage warning and critical levels
- sensitive listening ports
- Kubernetes detection
- GitLab detection
- GitLab memory/autostart regression check based on previous incident memory

Findings now include:

```text
rule_id
severity
category
title
detail
evidence
recommendation
requires_approval
command_suggestion
plugin
```

## Markdown reasoning

The endpoint below reasons over the current snapshot and Markdown runbooks under `knowledge/`:

```bash
curl -X POST http://127.0.0.1:8000/api/reason \
  -H 'Content-Type: application/json' \
  -d '{"question":"why is my GitLab server using high memory?"}' | jq
```

This is deterministic local reasoning/RAG-lite. It is intentionally not connected to an LLM yet. The next AI step is to pass this structured context to llama.cpp/Qwen.

## Guarded command executor

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

Read-only actions are auto-approved after validation. Run the returned action id:

```bash
curl -X POST http://127.0.0.1:8000/api/actions/<action-id>/run | jq
```

Propose a repair action:

```bash
curl -X POST http://127.0.0.1:8000/api/actions/propose \
  -H 'Content-Type: application/json' \
  -d '{
    "reason":"restart nginx after operator approval",
    "command":"systemctl",
    "args":["restart","nginx"],
    "kind":"repair"
  }' | jq
```

Approve first:

```bash
curl -X POST http://127.0.0.1:8000/api/actions/<action-id>/approve | jq
curl -X POST http://127.0.0.1:8000/api/actions/<action-id>/run | jq
```

Audit log:

```text
data/action_audit.jsonl
```

## Kubernetes plugin

Plugin file:

```text
src/plugins/kubernetes.rs
```

It detects:

- kubelet / kube-apiserver / etcd / kube-proxy / containerd processes
- `/etc/kubernetes`
- `/etc/kubernetes/manifests`
- `/var/lib/kubelet`
- `/var/lib/etcd`
- common `kubectl` binary locations

It suggests read-only commands only:

```text
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get events -A --sort-by=.lastTimestamp
```

## GitLab plugin

Plugin file:

```text
src/plugins/gitlab.rs
```

It detects:

- GitLab component processes
- `/etc/gitlab`
- `/opt/gitlab`
- `/var/opt/gitlab`
- `/var/log/gitlab`
- `gitlab-ctl`

It also encodes the previous incident pattern: GitLab auto-start on Red Hat can cause high CPU/RAM.

## systemd service

Files:

```text
packaging/systemd/osai-agent.service
packaging/systemd/osai-agent.env
```

Manual install example:

```bash
sudo useradd -r -s /sbin/nologin -d /var/lib/osai-agent osai || true
sudo mkdir -p /etc/osai-agent/knowledge /var/lib/osai-agent
sudo cp target/release/osai-agent /usr/bin/osai-agent
sudo cp knowledge/*.md /etc/osai-agent/knowledge/
sudo cp packaging/systemd/osai-agent.env /etc/osai-agent/osai-agent.env
sudo cp packaging/systemd/osai-agent.service /etc/systemd/system/osai-agent.service
sudo chown -R osai:osai /var/lib/osai-agent
sudo systemctl daemon-reload
sudo systemctl enable --now osai-agent
```

## RPM packaging for RHEL/CentOS

Files:

```text
packaging/rpm/osai-agent.spec
scripts/build-rpm.sh
```

Build on a RHEL-like host with Rust/Cargo and rpm-build installed:

```bash
sudo dnf install -y rust cargo rpm-build rsync systemd-rpm-macros
./scripts/build-rpm.sh
```

Expected output directory:

```text
~/rpmbuild/RPMS/
```

## API summary

```bash
curl http://127.0.0.1:8000/api/health
curl http://127.0.0.1:8000/api/snapshot | jq
curl -X POST http://127.0.0.1:8000/api/scan | jq
curl http://127.0.0.1:8000/api/history | jq
curl http://127.0.0.1:8000/api/knowledge | jq
curl http://127.0.0.1:8000/api/plugins | jq
curl http://127.0.0.1:8000/api/actions | jq
```

## Project structure

```text
osai-agent/
├── Cargo.toml
├── Cargo.lock
├── README.md
├── LICENSE
├── .env.storage.example
├── .env.cognee.example
├── docker-compose.storage.yml
├── config/
│   └── osai-agent.toml
├── docs/
│   ├── llama-qwen-cognee-rust-architecture.md
│   ├── phase3-storage-cognee.md
│   ├── rust-storage-worker.md
│   └── rust-to-cognee-to-qwen-data-flow.md
├── knowledge/
├── packaging/
│   ├── rpm/
│   │   └── osai-agent.spec
│   └── systemd/
│       ├── osai-agent.env
│       └── osai-agent.service
├── scripts/
│   ├── build-rpm.sh
│   ├── run-memory-worker.sh
│   └── setup-storage-venv.sh
├── src/
│   ├── actions.rs
│   ├── bin/
│   │   └── osai-storage-worker.rs
│   ├── history.rs
│   ├── knowledge.rs
│   ├── main.rs
│   ├── reasoning.rs
│   ├── rules.rs
│   ├── collector/
│   │   ├── mod.rs
│   │   ├── models.rs
│   │   ├── ports.rs
│   │   └── scanner.rs
│   └── plugins/
│       ├── gitlab.rs
│       ├── kubernetes.rs
│       └── mod.rs
├── storage/
│   ├── migrations/
│   └── postgres-init/
└── web/
    ├── index.html
    ├── app.css
    └── app.js
```

## Current architecture

The project is now Rust-first. The core project does not require a Python virtual environment.

```text
Browser / CLI / API
        |
        v
osai-agent Rust binary
  - scans Linux host
  - serves dashboard HTML/CSS/JS
  - exposes API
  - runs rules and guarded actions
        |
        v
osai-storage-worker Rust binary
  - reads scan history from osai-agent API
  - writes exact facts to PostgreSQL
  - writes raw snapshots to RustFS
  - writes compact memory rows to Cognee outbox tables
        |
        +--> PostgreSQL: facts, findings, history, outbox
        +--> RustFS: raw JSON snapshots and evidence files
        +--> optional Cognee service: memory, pgvector, Kuzu
        +--> optional llama.cpp/Qwen: local reasoning over retrieved context
```

Mental model:

```text
PostgreSQL = exact facts
RustFS = raw evidence files
pgvector = semantic memory search
Kuzu = relationships
Cognee = memory/retrieval layer
llama.cpp + Qwen3 = local inference
Rust = controller/orchestrator
```

Important: Qwen does not read PostgreSQL, RustFS, pgvector, or Kuzu by itself. Rust must fetch the right facts and memories, build a clean prompt, send that prompt to llama.cpp, and save the answer back.

## What is intentionally still not hardwired

Cognee direct ingestion is intentionally not hardwired into the Rust agent process. The Rust storage worker writes compact memory text into PostgreSQL and creates durable `osai_cognee_outbox` rows. A future Cognee HTTP service or stable Rust SDK can consume that outbox without changing the scanner, rules, dashboard, PostgreSQL schema, or RustFS snapshot archive.

---

## Phase 3: PostgreSQL + RustFS + Cognee Outbox

This phase adds durable production memory with a Rust-first worker.

Architecture:

```text
OSAI Rust Agent API
  -> Rust storage worker
      -> PostgreSQL: structured scan history, findings, host inventory, outbox
      -> RustFS/S3 object storage: raw full snapshot JSON objects
      -> Cognee outbox: compact AI memory waiting for external ingestion
```

### 1. Start PostgreSQL and RustFS

```bash
cp .env.storage.example .env.storage
cp .env.cognee.example .env.cognee
podman compose -f docker-compose.storage.yml up -d
# or:
docker compose -f docker-compose.storage.yml up -d
```

PostgreSQL creates two databases:

- `osai_agent` for OSAI operational tables
- `cognee_db` for Cognee's own relational state

RustFS runs as the on-prem S3-compatible object store:

```text
S3 API:  http://127.0.0.1:9000
Console: http://127.0.0.1:9001
username: rustfsadmin
password: rustfsadmin
```

Create this bucket once in the RustFS console before the first storage sync:

- `osai-agent`

If you already ran the older MinIO schema, migrate the PostgreSQL column names once:

```bash
psql 'postgresql://postgres:postgres_admin_password@127.0.0.1:5432/osai_agent' \
  -f storage/migrations/003-rename-minio-columns.sql
```

### 2. Run the Rust agent

```bash
cargo run -- --bind 127.0.0.1:8000 --scan-interval-seconds 30
```

If you expose the dashboard outside localhost, set a token:

```bash
export OSAI_AGENT_TOKEN='change-me-long-random-token'
cargo run -- --bind 0.0.0.0:8000 --api-token "$OSAI_AGENT_TOKEN"
```

### 3. Build the Rust storage worker

```bash
cargo build --release --bin osai-storage-worker
```

This replaces the old `.venv-storage/` Python worker. No Python virtual environment is required for PostgreSQL + RustFS + outbox persistence.

For local LLM/Cognee experimentation later, you can still run a separate Cognee service and point it at the outbox. Keep that outside the Rust scanner path.

If you are using local llama.cpp/Qwen later, run that service separately from this worker.

### 4. Run one sync cycle

```bash
./target/release/osai-storage-worker --once
```

Or use the wrapper:

```bash
./scripts/run-memory-worker.sh --once
```

### 5. Run continuously

```bash
./target/release/osai-storage-worker
```

Or:

```bash
./scripts/run-memory-worker.sh
```

### 6. Verify PostgreSQL storage

```bash
psql 'postgresql://osai:osai_password@127.0.0.1:5432/osai_agent' \
  -c 'select id, generated_at, hostname, highest_severity, finding_count from osai_scan_history order by generated_at desc limit 5;'
```

### 7. Verify Cognee outbox

```bash
psql 'postgresql://osai:osai_password@127.0.0.1:5432/osai_agent' \
  -c 'select id, scan_id, status, attempt_count, last_error from osai_cognee_outbox order by id desc limit 10;'
```

### 8. Verify RustFS objects

Open:

```text
http://127.0.0.1:9001
```

Then check the `osai-agent` bucket. The Rust worker stores raw snapshots under:

```text
snapshots/<hostname>/<generated-at>/<scan-id>.json
```

## Phase 4: llama.cpp + Qwen + Cognee memory path

This project is ready to use llama.cpp with `Qwen3-4B-Q4_K_M.gguf`, but the model is still a separate local inference server. The Rust binaries remain the controller.

Start llama.cpp:

```bash
./llama-server \
  -m /path/to/Qwen3-4B-Q4_K_M.gguf \
  --host 127.0.0.1 \
  --port 8080 \
  --alias osai-llm \
  -c 4096
```

Test the local model server:

```bash
curl http://127.0.0.1:8080/v1/models
```

Configure optional Cognee memory with:

```bash
cp .env.cognee.example .env.cognee
```

The example config points Cognee at:

```text
LLM_PROVIDER=custom
LLM_MODEL=openai/osai-llm
LLM_ENDPOINT=http://127.0.0.1:8080/v1
EMBEDDING_PROVIDER=fastembed
EMBEDDING_MODEL=sentence-transformers/all-MiniLM-L6-v2
GRAPH_DATABASE_PROVIDER=kuzu
VECTOR_DB_PROVIDER=pgvector
```

Data flow:

```text
Rust scanner
  -> PostgreSQL exact facts
  -> RustFS raw snapshot
  -> osai_memory_events compact memory text
  -> osai_cognee_outbox optional ingestion queue
  -> Cognee stores/searches memory with pgvector and Kuzu
  -> Rust retrieves facts + recalled memory
  -> Rust sends context to llama.cpp/Qwen
  -> Rust stores the answer and evidence references
```

Use this detailed architecture document for the complete reasoning path:

```text
docs/rust-to-cognee-to-qwen-data-flow.md
```

### Important design rule

Do not use Cognee as the only database for system state. Cognee is the AI memory/retrieval layer. PostgreSQL remains the operational source of truth and RustFS remains the raw evidence store. The Rust worker now prepares Cognee-ready memory rows without requiring Python dependencies in this project.
