# HostScope

HostScope is a vendor-neutral Rust toolkit for turning Linux host facts into one
versioned context document and exposing it through three deliberately separate
surfaces:

- JSON for storage, APIs, tests, and future adapters.
- OTLP metrics for SigNoz, an OpenTelemetry Collector, or another compatible
  observability backend.
- A read-only MCP server for AI clients that need controlled host context.

It targets bare-metal servers and Linux virtual machines running distributions
such as AlmaLinux, RHEL, Ubuntu, and Debian. The current contract is
`io.hostscope/snapshot/v1alpha1`.

> HostScope is a candidate standard plus a reference implementation, not an
> industry standard yet. Standard status requires independent implementations,
> conformance tests, governance, compatibility commitments, and adoption.

The normative alpha contract is in [SPECIFICATION.md](SPECIFICATION.md); the
Rust workspace is its reference implementation.

## Why all three layers are needed

| Layer | Primary job | What it deliberately does not do |
| --- | --- | --- |
| HostScope | Collect and normalize durable server facts | Store dashboards or decide how an LLM reasons |
| OpenTelemetry/OTLP | Carry metrics, traces, and logs to observability systems | Define a complete server inventory or AI tool API |
| MCP | Give an AI client discoverable resources and callable tools | Continuously stream time-series telemetry or discover host facts by itself |

OpenTelemetry answers “what is happening over time?” MCP answers “what context
or operation may an AI request now?” HostScope answers “what is this host, what
facts were observed, and what could not be collected?”

## Data flow

```mermaid
flowchart TD
    K["Linux /proc, /sys, os-release"] --> P["Bounded read-only probes"]
    P --> S["HostScope snapshot v1alpha1"]
    S --> J["JSON / database / RustFS"]
    S --> O["OTLP metric mapping"]
    O --> C["OpenTelemetry Collector"]
    C --> B["SigNoz or another backend"]
    S --> M["Read-only MCP resources and tools"]
    M --> A["OSAI or another AI client"]
```

The snapshot is the source of truth. OTLP and MCP are adapters. Replacing
SigNoz, adding Prometheus, or changing an MCP client does not change the host
collector or stored schema.

## What the first release collects

- Pseudonymous host identity and architecture.
- Distribution, version, kernel, and package family.
- CPU topology and frequency hints.
- Memory, swap, load, uptime, and aggregate process states.
- Filesystem capacity and mount mode.
- Network interface state and cumulative counters.
- Aggregate systemd service health.
- Bare-metal, VM, or container hints.
- SELinux, AppArmor, FIPS, kernel lockdown, and selected safe sysctls.
- Per-section collection status, permission failures, parser failures, and
  resource-limit failures.

It does **not** claim to know “everything.” Facts can be hidden by kernel
namespaces, permissions, containers, hardened `/proc`, missing tools, firmware,
or cloud APIs. HostScope makes those gaps explicit instead of inventing data.

## Quick start

Prerequisites: Rust 1.88 or newer and Linux.

```bash
cargo run -p hostscope -- snapshot --pretty
cargo run -p hostscope -- doctor
```

Set a private salt to get a stable host ID without emitting `/etc/machine-id`:

```bash
export HOSTSCOPE_IDENTITY_SALT="$(od -An -N32 -tx1 /dev/urandom | tr -d ' \n')"
cargo run -p hostscope -- snapshot --pretty
```

Never commit that salt. Use the same secret on hosts only if cross-host identity
correlation is intended.

## Send to SigNoz or any OTLP backend

If SigNoz already publishes OTLP/HTTP port `4318` on the host:

```bash
export OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318
cargo run --release -p hostscope -- watch --interval-seconds 15
```

The HTTP exporter appends `/v1/metrics`. To change observability vendors, point
the endpoint at a different OpenTelemetry Collector. HostScope itself has no
SigNoz SDK or vendor-specific field.

## Connect an AI client through MCP

The MCP server uses stdio, writes protocol messages only to stdout, and sends
logs to stderr:

```json
{
  "mcpServers": {
    "hostscope": {
      "command": "/usr/local/bin/hostscope",
      "args": ["--profile", "safe", "--redaction", "strict", "mcp"],
      "env": {
        "HOSTSCOPE_IDENTITY_SALT": "load-this-from-your-secret-manager"
      }
    }
  }
}
```

Exposed resources:

- `hostscope://snapshot/latest`
- `hostscope://schema/v1alpha1`
- `hostscope://policy/effective`

Exposed tools:

- `host_snapshot(section?, pretty?)`
- `host_health_summary()`

There is no arbitrary shell tool and no mutation tool. If remote MCP is added,
put it behind OAuth 2.1, TLS, per-tool authorization, rate limits, and audit
logging; do not simply expose the stdio process on a public port.

## Native one-command install

Native installation is recommended because a normal container sees its own
PID, mount, and network namespaces rather than the host. Giving a container
enough access to inspect the host often creates a larger security risk.

```bash
./scripts/install.sh
```

The installer builds the release binary, generates a private identity salt if
needed, installs a hardened systemd service, and starts `hostscope watch`. Edit
`/etc/hostscope/hostscope.env` to change the OTLP endpoint.

## Repository layout

```text
crates/hostscope-core  Versioned schema, policies, Linux collectors, fixtures
crates/hostscope-otel  OpenTelemetry semantic-convention mapping and OTLP export
crates/hostscope       CLI, daemon loop, doctor command, read-only MCP server
spec/                  Committed machine-readable v1alpha1 JSON Schema
config/                Environment configuration example
deploy/                systemd and OpenTelemetry Collector examples
docs/                  Architecture, comparison, schema, security, integration
```

## Enterprise boundaries

This repository includes bounded inputs/outputs, fixture tests for Ubuntu and
AlmaLinux, schema versioning, pseudonymous identifiers, explicit partial
results, a hardened service unit, dependency policy, and CI checks. Before a
production-wide rollout, also add your organization’s code review, signed
release pipeline, SBOM and provenance, secrets manager, canary deployment,
retention policy, SLOs, and independent security review.

See [Architecture](docs/ARCHITECTURE.md), [comparison](docs/COMPARISON.md),
[schema contract](docs/SCHEMA.md), [security model](docs/SECURITY.md), and the
[OSAI integration guide](docs/OSAI-INTEGRATION.md). The exact build and runtime
checks are recorded in [VALIDATION.md](VALIDATION.md).

## Primary specifications used

- [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/)
- [OpenTelemetry semantic conventions](https://opentelemetry.io/docs/specs/semconv/)
- [System metric semantic conventions](https://opentelemetry.io/docs/specs/semconv/system/system-metrics/)
- [OpenTelemetry Rust OTLP exporter](https://docs.rs/opentelemetry-otlp/latest/opentelemetry_otlp/)
- [MCP architecture](https://modelcontextprotocol.io/docs/learn/architecture)
- [Official MCP Rust SDK](https://github.com/modelcontextprotocol/rust-sdk)
- [`os-release` specification](https://www.freedesktop.org/software/systemd/man/latest/os-release.html)
- [Linux userspace ABI documentation](https://docs.kernel.org/admin-guide/abi.html)
