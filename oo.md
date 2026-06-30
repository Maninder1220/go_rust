# OSAI Agent Codebase Guide

This guide explains the OSAI Agent Phase 3 codebase, the complete stack, the folder structure, what each component does, how the data flows, and how to run/access the project from browser, CLI, and API.

---

## 1. What this project is

OSAI Agent is a Rust-first local infrastructure agent for Linux/DevOps operations.

Its current job is to:

1. Scan the local machine.
2. Detect OS, CPU, RAM, disk, ports, processes, service hints, Kubernetes hints, and GitLab hints.
3. Run a local rule engine against the scan.
4. Show findings in a browser dashboard.
5. Expose findings through HTTP APIs.
6. Store scan history locally in JSONL.
7. Optionally sync scans into PostgreSQL, MinIO, and Cognee through a Python memory worker.
8. Keep repair commands behind a guarded approval workflow.

The project is intentionally split into two layers:

```text
Layer 1: Rust Agent
- Fast scanner
- Dashboard
- API
- Rule engine
- Local history
- Guarded actions

Layer 2: Storage + AI Memory Worker
- PostgreSQL structured storage
- MinIO raw snapshot/object storage
- Cognee memory ingestion
- llama.cpp local LLM endpoint for Cognee
```

This split is important because the scanner may later run with OS-level permissions. Keeping AI/database code outside the scanner makes the trusted Rust binary smaller and safer.

---

## 2. Complete architecture

```text
                                  Browser Dashboard
                                         |
                                         | http://127.0.0.1:8000
                                         v
+-----------------------------------------------------------------------------------+
|                              Rust OSAI Agent Binary                                |
|-----------------------------------------------------------------------------------|
| Axum HTTP server                                                                  |
| Embedded HTML/CSS/JS dashboard                                                     |
| API endpoints                                                                      |
| Background scanner                                                                 |
| Rule engine                                                                        |
| Markdown knowledge search                                                          |
| Guarded command approval workflow                                                  |
| Local JSONL history                                                                |
+-----------------------------------------------------------------------------------+
        |                         |                         |
        |                         |                         |
        v                         v                         v
 data/scan_history.jsonl   data/action_audit.jsonl    knowledge/*.md


                         Python Memory Worker
                                  |
                                  | pulls /api/history from Rust Agent
                                  v
+-----------------------------------------------------------------------------------+
|                                Storage + AI Layer                                  |
|-----------------------------------------------------------------------------------|
| PostgreSQL: structured scan history, findings, hosts, outbox                       |
| MinIO: full raw JSON scan snapshots                                                |
| Cognee: long-term AI memory, graph/vector/relational memory layer                  |
| llama.cpp: local OpenAI-compatible LLM endpoint for Cognee                         |
| FastEmbed or another embedding provider: vector embeddings                         |
+-----------------------------------------------------------------------------------+
```

---

## 3. Current stack

### Core application stack

| Layer | Technology | Purpose |
|---|---|---|
| Language | Rust | Main scanner, web server, API, rule engine, guarded actions |
| Web framework | Axum | HTTP routing and API handling |
| Async runtime | Tokio | Background scan loop, async HTTP server, command execution |
| System inspection | sysinfo + `/proc/net` parsing | CPU, memory, disk, network, processes, listening ports |
| Frontend serving | include_dir + embedded `web/` folder | Browser dashboard inside the compiled Rust binary |
| Serialization | Serde + serde_json | JSON API responses and JSONL history |
| CLI parsing | Clap | Flags such as `--bind`, `--data-dir`, `--scan-interval-seconds` |
| Logging | tracing + tracing-subscriber | Structured runtime logs |

### Storage and memory stack

| Layer | Technology | Purpose |
|---|---|---|
| Operational DB | PostgreSQL | Structured scan history, findings, hosts, outbox rows |
| Vector support | pgvector image | Used by Cognee/vector memory when configured |
| Object storage | MinIO | Raw full scan snapshots as JSON objects |
| AI memory | Cognee | Remember scans and Markdown runbooks as searchable connected memory |
| Local LLM | llama.cpp `llama-server` | Local OpenAI-compatible endpoint for Cognee reasoning/extraction |
| Embeddings | FastEmbed or OpenAI-compatible embeddings | Converts text into vectors for semantic search |
| Worker runtime | Python venv | Memory sync bridge between Rust Agent, PostgreSQL, MinIO, and Cognee |

---

## 4. Can the full stack run as one Rust binary?

### Short answer

The **Rust agent core** can run as a single binary. The **entire production stack** should not be forced into one Rust binary.

### What can be inside the Rust binary

The current Rust binary already includes:

```text
- HTTP server
- REST API
- Dashboard static files
- OS scanner
- Rule engine
- Markdown knowledge loader/search
- Guarded command executor
- Local JSONL history writer
```

This is possible because the `web/` directory is embedded at compile time using `include_dir`.

### What should stay outside the Rust binary

These should stay as separate services:

```text
- PostgreSQL
- MinIO
- Cognee
- llama.cpp server
```

Reason:

1. PostgreSQL is a database server with its own storage engine, WAL, indexes, users, permissions, and backups.
2. MinIO is an object storage server with S3-style APIs, buckets, access keys, and object metadata.
3. Cognee is a Python-based AI memory framework with relational/vector/graph storage integrations.
4. llama.cpp is a model runtime/server that loads GGUF model files and exposes inference endpoints.

Trying to embed all of these into one Rust binary would make the agent heavy, fragile, harder to upgrade, and harder to secure.

### Better production packaging options

Use one of these:

```text
Option A: One Rust binary + docker compose for storage/AI services
Option B: One RPM installs Rust binary + systemd unit + compose file
Option C: One installer script sets up Rust agent, PostgreSQL, MinIO, Cognee, llama.cpp
Option D: Kubernetes deployment later
```

For your project, Option A or B is best right now.

---

## 5. Folder structure

```text
osai-agent/
├── Cargo.toml
├── README.md
├── LICENSE
├── .env.storage.example
├── .env.cognee.example
├── docker-compose.storage.yml
│
├── src/
│   ├── main.rs
│   ├── actions.rs
│   ├── history.rs
│   ├── knowledge.rs
│   ├── reasoning.rs
│   ├── rules.rs
│   │
│   ├── collector/
│   │   ├── mod.rs
│   │   ├── models.rs
│   │   ├── ports.rs
│   │   └── scanner.rs
│   │
│   └── plugins/
│       ├── mod.rs
│       ├── kubernetes.rs
│       └── gitlab.rs
│
├── web/
│   ├── index.html
│   ├── app.css
│   └── app.js
│
├── knowledge/
│   ├── 00_agent_identity.md
│   ├── 01_server_profile.md
│   ├── 02_allowed_commands.md
│   ├── 03_guardrails.md
│   ├── 04_kubernetes_runbook.md
│   ├── 05_linux_runbook.md
│   ├── 06_gitlab_incidents.md
│   ├── 07_troubleshooting_patterns.md
│   ├── 08_etc.md
│   └── 08_response_format.md
│
├── storage/
│   ├── postgres-init/
│   │   ├── 001-create-databases.sh
│   │   └── 002-osai-schema.sql
│   │
│   └── cognee_bridge/
│       ├── requirements.txt
│       ├── osai_memory_worker.py
│       └── ingest_knowledge_to_cognee.py
│
├── scripts/
│   ├── setup-storage-venv.sh
│   ├── run-memory-worker.sh
│   └── build-rpm.sh
│
├── config/
│   └── osai-agent.toml
│
├── packaging/
│   ├── rpm/
│   │   └── osai-agent.spec
│   └── systemd/
│       ├── osai-agent.env
│       └── osai-agent.service
│
└── docs/
    ├── phase3-storage-cognee.md
    └── OSAI_AGENT_CODEBASE_GUIDE.md
```

---

## 6. Rust codebase explained

### `src/main.rs`

This is the application entrypoint.

It does these jobs:

1. Parses CLI flags using Clap.
2. Loads Markdown knowledge from `knowledge/`.
3. Creates the local history store in `data/scan_history.jsonl`.
4. Creates the guarded action store in `data/action_audit.jsonl`.
5. Runs the first system scan.
6. Starts a background scan loop.
7. Builds the Axum router.
8. Serves API endpoints.
9. Serves embedded dashboard files from `web/`.
10. Refuses public binding without token unless explicitly allowed.

Important routes:

```text
GET  /api/health
GET  /api/snapshot
POST /api/scan
GET  /api/history
GET  /api/history/{id}
GET  /api/knowledge
GET  /api/knowledge/{name}
POST /api/reason
GET  /api/plugins
GET  /api/actions
POST /api/actions/propose
POST /api/actions/{id}/approve
POST /api/actions/{id}/run
GET  /
```

The dashboard is served from embedded files, not from disk at runtime.

---

### `src/collector/models.rs`

This file defines the data structures returned by the scanner.

Main structure:

```rust
pub struct Snapshot {
    pub generated_at: String,
    pub host: HostInfo,
    pub os: OsInfo,
    pub compute: ComputeInfo,
    pub memory: MemoryInfo,
    pub storage: Vec<DiskInfo>,
    pub network: Vec<NetworkInfo>,
    pub listening_ports: Vec<ListeningPort>,
    pub top_processes: Vec<ProcessInfo>,
    pub service_hints: Vec<ServiceHint>,
    pub app_hints: Vec<AppHint>,
    pub database_hints: Vec<AppHint>,
    pub kubernetes: KubernetesHint,
    pub gitlab: GitlabHint,
    pub findings: Vec<Finding>,
}
```

This is the main JSON object returned by:

```text
GET /api/snapshot
POST /api/scan
GET /api/history/{id}
```

---

### `src/collector/scanner.rs`

This file performs the OS scan.

It collects:

```text
- hostname
- uptime
- boot time
- OS version
- kernel version
- CPU usage
- memory usage
- swap usage
- disk usage
- network counters
- top processes
- listening ports
- service hints
- app hints
- database hints
- Kubernetes hints
- GitLab hints
```

Then it passes the collected state into the rule engine:

```rust
evaluate_rules(RuleContext { ... })
```

The final output is a `Snapshot`.

---

### `src/collector/ports.rs`

This file reads Linux kernel networking files directly:

```text
/proc/net/tcp
/proc/net/tcp6
/proc/net/udp
/proc/net/udp6
```

It extracts listening ports and converts Linux socket state hex codes such as `0A` into human-readable states such as `LISTEN`.

This avoids depending only on shell commands like `ss` or `netstat`.

---

### `src/rules.rs`

This is the deterministic rule engine.

It currently checks:

```text
- high memory usage
- high CPU usage
- high disk usage
- sensitive listening ports
- Kubernetes detected
- GitLab detected
- GitLab with memory pressure
- GitLab with swap usage
```

Rules produce `Finding` objects.

Example finding fields:

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

Important design: rules do **not** automatically repair anything. They only create findings and recommendations.

---

### `src/history.rs`

This file stores local scan history.

It writes one JSON record per line into:

```text
data/scan_history.jsonl
```

This format is called JSONL.

Why JSONL is useful:

```text
- append-friendly
- easy to inspect with cat/jq
- durable enough for local phase
- no database needed for core binary
```

The memory worker later reads this history indirectly through the HTTP API and syncs it into PostgreSQL/MinIO/Cognee.

---

### `src/knowledge.rs`

This file loads Markdown files from:

```text
knowledge/*.md
```

It provides:

```text
- list all knowledge files
- read a specific knowledge file
- keyword search over Markdown content
```

This is currently deterministic local retrieval, not full vector RAG inside Rust.

---

### `src/reasoning.rs`

This file performs local reasoning over:

```text
- the current snapshot
- rule findings
- Markdown knowledge search results
```

It returns:

```text
status
evidence
likely_cause
safe_checks
suggested_action
risk
matched_findings
knowledge_matches
note
```

Current reasoning is deterministic. It does not require an LLM.

Cognee + llama.cpp is added as the external memory/AI layer.

---

### `src/actions.rs`

This file implements guarded command execution.

Workflow:

```text
1. Propose action
2. Validate command against allowlist
3. Mark read-only commands as approved
4. Mark repair commands as proposed
5. Require explicit approval for repair commands
6. Run only approved commands
7. Save audit trail in data/action_audit.jsonl
```

Blocked programs include:

```text
rm
mkfs
dd
shred
wipefs
reboot
shutdown
bash
sh
sudo
```

Allowed examples include:

```text
df
free
ss
ps
du
systemctl status
systemctl is-active
systemctl is-enabled
systemctl restart
journalctl -u
kubectl get
kubectl describe
kubectl logs
gitlab-ctl status
```

Important: even though `systemctl restart` is allowed by validation, it is classified as a repair action and requires approval.

---

### `src/plugins/kubernetes.rs`

This detects Kubernetes signals.

It looks for process/service hints such as:

```text
kubelet
containerd
kubectl
kube-apiserver
```

It returns safe read-only commands such as:

```text
kubectl get nodes -o wide
kubectl get pods -A -o wide
kubectl get events -A --sort-by=.lastTimestamp
```

---

### `src/plugins/gitlab.rs`

This detects GitLab signals.

It looks for GitLab-related process hints such as:

```text
gitlab
gitlab-workhorse
gitaly
sidekiq
puma
```

It returns safe read-only commands such as:

```text
gitlab-ctl status
free -m
ps aux --sort=-%mem
```

---

## 7. Frontend/dashboard files

### `web/index.html`

Main dashboard HTML.

### `web/app.css`

Dashboard styling.

### `web/app.js`

Browser-side JavaScript.

It calls API endpoints such as:

```text
/api/health
/api/snapshot
/api/history
/api/reason
/api/actions
```

Because these files are embedded into the Rust binary, after you build the project, the binary can serve the dashboard without needing an external `web/` folder at runtime.

---

## 8. Storage layer explained

### `docker-compose.storage.yml`

Starts:

```text
osai-postgres
osai-minio
osai-minio-init
```

PostgreSQL is exposed on:

```text
127.0.0.1:5432
```

MinIO API is exposed on:

```text
127.0.0.1:9000
```

MinIO browser console is exposed on:

```text
http://127.0.0.1:9001
```

---

### `storage/postgres-init/001-create-databases.sh`

Creates database users and databases for:

```text
osai_agent
cognee_db
```

The idea is:

```text
osai_agent = your operational scan database
cognee_db  = Cognee-owned database
```

Keep them separate so Cognee can manage its own schema without mixing with your operational tables.

---

### `storage/postgres-init/002-osai-schema.sql`

Creates OSAI tables:

```text
osai_hosts
osai_scan_history
osai_findings
osai_cognee_outbox
osai_memory_events
```

Table purpose:

| Table | Purpose |
|---|---|
| `osai_hosts` | One row per host/machine |
| `osai_scan_history` | One row per scan, includes JSONB snapshot and MinIO object pointer |
| `osai_findings` | Normalized findings extracted from each scan |
| `osai_cognee_outbox` | Durable queue for Cognee ingestion |
| `osai_memory_events` | Text memory events prepared for Cognee |

---

## 9. Memory worker explained

### `storage/cognee_bridge/osai_memory_worker.py`

This is the bridge between the Rust agent and the storage/AI layer.

Flow:

```text
1. Load `.env.storage` and `.env.cognee`
2. Call Rust Agent API: /api/history
3. For each scan id, call /api/history/{id}
4. Save structured scan metadata to PostgreSQL
5. Save full raw scan JSON to MinIO
6. Create outbox row for Cognee
7. Send compact memory text to Cognee with cognee.remember(...)
```

Why this worker exists:

```text
Rust Agent should stay small and safe.
Python/Cognee dependency tree is large.
Storage and memory can fail/retry without crashing scanner.
Outbox makes ingestion durable.
```

---

### `storage/cognee_bridge/ingest_knowledge_to_cognee.py`

This script sends your Markdown runbooks into Cognee.

Input:

```text
knowledge/*.md
```

Output:

```text
Cognee dataset: osai-agent-knowledge
```

This is separate from scan memory.

Scan memory goes to:

```text
osai-agent-memory
```

Runbook memory goes to:

```text
osai-agent-knowledge
```

---

## 10. Data flow: scan to storage to memory

```text
Rust Agent background scanner
        |
        v
Snapshot object
        |
        +--> data/scan_history.jsonl
        |
        +--> Browser dashboard via /api/snapshot
        |
        +--> Memory worker pulls /api/history/{id}
                    |
                    +--> PostgreSQL osai_scan_history
                    +--> PostgreSQL osai_findings
                    +--> MinIO snapshots/<host>/<timestamp>/<scan-id>.json
                    +--> PostgreSQL osai_cognee_outbox
                    +--> Cognee remember(content, dataset_name="osai-agent-memory")
```

---

## 11. How to run the core Rust agent

From project root:

```bash
cargo run -- --bind 127.0.0.1:8000 --scan-interval-seconds 30
```

Open browser:

```text
http://127.0.0.1:8000
```

Run manual scan:

```bash
curl -X POST http://127.0.0.1:8000/api/scan
```

Get current snapshot:

```bash
curl http://127.0.0.1:8000/api/snapshot | jq
```

Get recent history:

```bash
curl 'http://127.0.0.1:8000/api/history?limit=5' | jq
```

Ask local deterministic reasoning:

```bash
curl -X POST http://127.0.0.1:8000/api/reason \
  -H 'Content-Type: application/json' \
  -d '{"question":"why is my GitLab using memory?"}' | jq
```

---

## 12. How to build one Rust binary

```bash
cargo build --release
```

Binary path:

```text
target/release/osai-agent
```

Run binary directly:

```bash
./target/release/osai-agent --bind 127.0.0.1:8000 --scan-interval-seconds 30
```

Because the frontend is embedded, this binary serves the dashboard too.

---

## 13. How to expose dashboard on LAN/browser

Local only:

```bash
./target/release/osai-agent --bind 127.0.0.1:8000
```

LAN/public bind requires token:

```bash
export OSAI_AGENT_TOKEN='change-this-long-random-token'
./target/release/osai-agent --bind 0.0.0.0:8000 --api-token "$OSAI_AGENT_TOKEN"
```

From another machine on same LAN:

```text
http://SERVER_IP:8000
```

If firewall is enabled, allow port 8000.

Ubuntu UFW:

```bash
sudo ufw allow 8000/tcp
```

RHEL/CentOS firewalld:

```bash
sudo firewall-cmd --add-port=8000/tcp --permanent
sudo firewall-cmd --reload
```

---

## 14. API authentication

If token is enabled, send this header:

```text
x-osai-token: your-token
```

Example:

```bash
curl http://127.0.0.1:8000/api/snapshot \
  -H "x-osai-token: $OSAI_AGENT_TOKEN" | jq
```

Without token, public binding is blocked by default.

This is intentional because the agent exposes host information and guarded action APIs.

---

## 15. How to run storage stack

Copy env files:

```bash
cp .env.storage.example .env.storage
cp .env.cognee.example .env.cognee
```

Start PostgreSQL and MinIO:

```bash
docker compose -f docker-compose.storage.yml up -d
```

or:

```bash
podman compose -f docker-compose.storage.yml up -d
```

Check containers:

```bash
docker ps
```

Expected:

```text
osai-postgres
osai-minio
```

---

## 16. How to run memory worker

Install Python dependencies:

```bash
./scripts/setup-storage-venv.sh
```

Run one sync cycle:

```bash
./scripts/run-memory-worker.sh --once
```

Run forever:

```bash
./scripts/run-memory-worker.sh
```

For early testing without Cognee:

```bash
COGNEE_ENABLED=false ./scripts/run-memory-worker.sh --once
```

---

## 17. How to check PostgreSQL

Enter Postgres container:

```bash
docker exec -it osai-postgres psql -U postgres -d osai_agent
```

Show tables:

```sql
\dt
```

Check scan history:

```sql
select id, generated_at, hostname, highest_severity, finding_count
from osai_scan_history
order by generated_at desc
limit 5;
```

Check findings:

```sql
select scan_id, severity, category, title
from osai_findings
order by created_at desc
limit 10;
```

Check Cognee outbox:

```sql
select id, scan_id, dataset_name, status, attempt_count, last_error
from osai_cognee_outbox
order by created_at desc
limit 10;
```

Exit:

```sql
\q
```

---

## 18. How to check MinIO

Open browser:

```text
http://127.0.0.1:9001
```

Login:

```text
Username: minioadmin
Password: minioadmin
```

Open bucket:

```text
osai-agent
```

Expected object path:

```text
snapshots/<hostname>/<timestamp>/<scan-id>.json
```

Command-line check:

```bash
docker exec -it osai-minio sh
mc alias set local http://127.0.0.1:9000 minioadmin minioadmin
mc ls --recursive local/osai-agent
```

---

## 19. How llama.cpp fits

Cognee needs an LLM provider for knowledge extraction/reasoning tasks.

You are using llama.cpp instead of Ollama.

That means Cognee should point to a llama.cpp OpenAI-compatible server:

```text
http://127.0.0.1:8081/v1
```

Start llama.cpp server:

```bash
llama-server \
  -m /full/path/to/actual-model.gguf \
  --host 127.0.0.1 \
  --port 8081 \
  --alias osai-llm \
  -c 4096
```

Do not use these files as models:

```text
ggml-vocab-*.gguf
```

Those are vocabulary/tokenizer test files, not full model weights.

Use a real model file such as:

```text
Qwen3-4B-Q4_K_M.gguf
```

Test server:

```bash
curl http://127.0.0.1:8081/v1/models
```

Test chat:

```bash
curl http://127.0.0.1:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer sk-no-key-required" \
  -d '{
    "model": "osai-llm",
    "messages": [
      {"role": "user", "content": "Reply with only: llama.cpp working"}
    ],
    "temperature": 0
  }'
```

---

## 20. Recommended `.env.cognee` for llama.cpp

Use absolute paths for Cognee directories.

Example:

```bash
DB_PROVIDER=postgres
DB_HOST=127.0.0.1
DB_PORT=5432
DB_USERNAME=cognee
DB_PASSWORD=cognee_password
DB_NAME=cognee_db

SYSTEM_ROOT_DIRECTORY=/home/mone/osai-agent/data/cognee_system
DATA_ROOT_DIRECTORY=/home/mone/osai-agent/data/cognee_data

GRAPH_DATABASE_PROVIDER=kuzu
VECTOR_DB_PROVIDER=pgvector

LLM_PROVIDER=custom
LLM_MODEL=openai/osai-llm
LLM_ENDPOINT=http://127.0.0.1:8081/v1
LLM_API_KEY=sk-no-key-required
LLM_INSTRUCTOR_MODE=json_mode
LLM_TEMPERATURE=0
LLM_MAX_COMPLETION_TOKENS=2048

EMBEDDING_PROVIDER=fastembed
EMBEDDING_MODEL=sentence-transformers/all-MiniLM-L6-v2
EMBEDDING_DIMENSIONS=384
```

Replace `/home/mone/osai-agent` with your real project path.

---

## 21. Important dependencies explained

### Rust dependencies

| Dependency | Used in | Purpose |
|---|---|---|
| `anyhow` | whole app | Easier error handling |
| `axum` | `main.rs` | HTTP server, routes, handlers |
| `chrono` | history/actions/scanner | Timestamps |
| `clap` | `main.rs` | CLI flags |
| `include_dir` | `main.rs` | Embed `web/` folder into binary |
| `mime_guess` | `main.rs` | Correct content-type for embedded files |
| `serde` | models/API | Convert structs to/from JSON |
| `serde_json` | history/storage | JSON and JSONL |
| `sysinfo` | scanner | CPU, memory, disk, processes, OS info |
| `tokio` | runtime | Async server, background loop, command execution |
| `tower-http` | HTTP layer | Request tracing and CORS support |
| `tracing` | logs | Runtime logging |
| `tracing-subscriber` | logs | Log formatting/filtering |

### Python worker dependencies

| Dependency | Purpose |
|---|---|
| `requests` | Calls Rust Agent API |
| `python-dotenv` | Loads `.env.storage` and `.env.cognee` |
| `psycopg` | Connects to PostgreSQL |
| `minio` | Uploads JSON snapshots to MinIO |
| `cognee` | Sends scan memory and Markdown knowledge into Cognee |

Cognee itself pulls many transitive packages. That is normal because it supports LLM providers, embeddings, vector stores, graph stores, structured extraction, and API layers.

---

## 22. Common commands

### Run Rust agent

```bash
cargo run -- --bind 127.0.0.1:8000 --scan-interval-seconds 30
```

### Build binary

```bash
cargo build --release
```

### Run binary

```bash
./target/release/osai-agent --bind 127.0.0.1:8000
```

### Start storage

```bash
docker compose -f docker-compose.storage.yml up -d
```

### Run worker once

```bash
./scripts/run-memory-worker.sh --once
```

### Open dashboard

```text
http://127.0.0.1:8000
```

### Open MinIO console

```text
http://127.0.0.1:9001
```

---

## 23. Development path from here

Recommended next steps:

1. Fix `.env.cognee.example` to use llama.cpp instead of Ollama for your setup.
2. Add a `/api/memory/search` endpoint that queries Cognee recall.
3. Add Rust-side PostgreSQL writes later only if needed.
4. Add proper dashboard login instead of only API token header.
5. Add systemd unit for the memory worker.
6. Add systemd unit for llama.cpp server.
7. Add backup/export commands for PostgreSQL and MinIO.
8. Add multi-host identity and enrollment.
9. Add command approval UI improvements.
10. Add signed action logs.

---

## 24. Mental model

Remember this simple model:

```text
Rust Agent = eyes, rules, dashboard, guarded hands
PostgreSQL = structured memory
MinIO = raw evidence vault
Cognee = AI memory brain
llama.cpp = local LLM engine
Python worker = bridge between scanner and AI/storage world
```

The Rust binary should remain the trusted core.

The storage/AI layer should remain pluggable and replaceable.
