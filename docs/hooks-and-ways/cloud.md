# Cloud Platform Ways

Guidance for working with cloud provider CLI tools.

## Domain Scope

This covers CLI-driven interaction with cloud platforms: AWS, Google Cloud, Azure, and Cloudflare. The focus is on CLI tool usage patterns, authentication, region awareness, and cost consciousness - not cloud architecture (that's a design discussion) or infrastructure-as-code (that's a potential future domain).

## Principles

### CLI tools are the interface

We use `aws`, `gcloud`, `az`, and `wrangler` directly. Not web consoles, not Terraform (that's a different concern), not SDKs. The CLI is the common ground between interactive exploration and scriptable automation.

### Authentication is not optional

Every CLI session starts with valid credentials. Check auth status before running commands. Expired tokens cause confusing errors that waste time.

### Region and project context matter

Cloud commands execute against a specific region/project/subscription. Wrong context = wrong resources. Always be explicit about context or verify the default.

### Cost awareness is a first-class concern

Cloud resources cost money. Creating resources is easy; remembering to clean them up is hard. Flag resource creation, suggest cleanup, and prefer spot/preemptible/dev-tier when the use case allows.

---

## Ways

### aws

**Principle**: AWS CLI operations should be context-aware (profile, region) and credential-safe.

**Triggers on**: Running `aws` commands or mentioning AWS services.

**Guidance direction**: Check `aws sts get-caller-identity` for auth status. Always specify `--region` or verify `AWS_DEFAULT_REGION`. Use `--output json` for scriptable output. For resource creation, flag the cost implications. For S3 operations, be aware of bucket region constraints.

### gcloud

**Principle**: Google Cloud CLI operations require project and auth context.

**Triggers on**: Running `gcloud` commands or mentioning GCP services.

**Guidance direction**: Check `gcloud auth list` and `gcloud config get-value project`. Use `gcloud config configurations` for switching between projects. Be explicit about region/zone. For resource creation, suggest labels for tracking.

### azure

**Principle**: Azure CLI operations require subscription and resource group context.

**Triggers on**: Running `az` commands or mentioning Azure services.

**Guidance direction**: Check `az account show` for current subscription. Resource groups are the organizational unit - always specify one. Use `--output table` for human-readable output, `--output json` for scripting.

### cloudflare

**Principle**: Cloudflare operations via wrangler for Workers, or the API for DNS and other services.

**Triggers on**: Running `wrangler` or `cf` commands, or mentioning Cloudflare services.

**Guidance direction**: For Workers: `wrangler` is the primary tool. Check `wrangler whoami` for auth. For DNS and other services: use the Cloudflare API via curl with the API token. Be cautious with DNS changes - propagation means mistakes are slow to fix.
