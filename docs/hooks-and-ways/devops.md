# DevOps / Platform Engineering Ways

Guidance for CI/CD, containers, infrastructure-as-code, and developer experience.

## Domain Scope

This covers the platform layer between application code and running systems: build pipelines, container images, infrastructure definitions, observability, and the developer experience tooling that ties them together. It's distinct from sysadmin (individual machines) and cloud (provider CLIs) - this is about the engineering systems that ship and run software.

## Principles

### Platform engineering is a product discipline

The platform serves developers. Its quality is measured by developer productivity, not by the sophistication of the tooling. A simple pipeline that developers understand beats an elegant one they can't debug.

### Pipelines should be debuggable locally

If a CI failure can only be reproduced in CI, the feedback loop is too slow. Pipeline steps should be runnable locally. Containers help here - if the build runs in a container, it runs the same everywhere.

### Infrastructure-as-code is code

IaC deserves the same rigor as application code: version control, review, testing, modularity. A Terraform module is a software component. Treat it like one.

### Observability is not optional

If you can't see what a system is doing, you can't operate it. Logging, metrics, and tracing are part of the system, not afterthoughts. Instrument at deploy time, not after the first incident.

---

## Ways

### pipelines

**Principle**: CI/CD pipelines should be fast, debuggable, and locally reproducible.

**Triggers on**: Editing pipeline configs (`.github/workflows/`, `Jenkinsfile`, `.gitlab-ci.yml`, `azure-pipelines.yml`), or mentioning CI/CD.

**Guidance direction**: Keep pipeline steps small and named clearly. Cache aggressively (dependencies, build artifacts). Fail fast - lint and type-check before test suites. Use matrix builds for multi-platform. For GitHub Actions specifically: pin action versions to SHAs, not tags.

### containers

**Principle**: Container images should be minimal, reproducible, and secure.

**Triggers on**: Editing `Dockerfile`, `docker-compose.yml`, `compose.yaml`, running `docker` or `podman` commands.

**Guidance direction**: Multi-stage builds to separate build deps from runtime. Pin base image digests, not just tags. Don't run as root. Use `.dockerignore`. For compose: use named volumes for persistence, health checks for dependencies, and explicit networks.

### iac

**Principle**: Infrastructure definitions are software components that deserve engineering rigor.

**Triggers on**: Editing `.tf`, `terraform`, `pulumi`, `cdktf` files, or running `terraform`/`pulumi` commands.

**Guidance direction**: State management is critical - remote state with locking. Modularize by concern, not by resource type. Use variables with validation. Plan before apply, always. For destructive changes, review the plan carefully. Tag all resources for cost attribution.

### monitoring

**Principle**: Observability should be built in, not bolted on.

**Triggers on**: Mentioning monitoring, alerting, logging, metrics, tracing, or observability tools (Prometheus, Grafana, Datadog, etc.).

**Guidance direction**: Structure logs as JSON for queryability. Use log levels meaningfully (ERROR = needs attention, WARN = degraded, INFO = business events, DEBUG = development). For metrics: RED method for services (Rate, Errors, Duration), USE method for resources (Utilization, Saturation, Errors). Alert on symptoms, not causes.
