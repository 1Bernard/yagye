# AWS Integration Guide — Yagye

This is a step-by-step guide for integrating Yagye's services with AWS, using Floci as the
local emulator. Each service has: what it does, the Floci simulation, verification steps,
what to watch out for locally, and what changes when you switch to real AWS at P22.

Work through these in order. Test and verify each one before moving to the next.
Run the full end-to-end test at the bottom after all services are live.

---

## Floci service availability

| AWS Service        | Floci | Status        | Yagye use                      |
|--------------------|-------|---------------|-------------------------------|
| S3                 | ✓     | Available     | KYB docs, data lake, exports   |
| KMS                | ✓     | Available     | KYB document encryption        |
| Secrets Manager    | ✓     | Available     | DB passwords, API keys         |
| Parameter Store    | ✓     | Available     | App config, feature flags      |
| SES Mailbox        | ✓     | Available     | Portal transactional email     |
| EventBridge        | ✓     | Available     | Data lake cron, scheduled jobs |
| SQS                | ✓     | Available     | Webhook DLQ (future)           |
| CloudWatch Logs    | ✓     | Available     | Log forwarding at P22          |
| ElastiCache        | ✗     | Not in Floci  | Redis container used instead   |
| MSK (Kafka)        | ✗     | Not in Floci  | Redpanda container used instead|
| ECR                | ✗     | Not in Floci  | Docker Hub or direct push P22  |
| Containers (ECS)   | ✗     | Coming soon   | Docker Compose used instead    |
| Cloud Scheduler    | ✗     | Coming soon   | Use EventBridge directly       |
| ALB                | ✗     | Not in Floci  | Caddy/Nginx on EC2 at P22      |
| RDS                | ✓     | Available     | Postgres containers used now   |

All Floci services run on a single port: `http://floci:4566` (inside Docker) or
`http://localhost:4566` (from your host machine).

CLI shortcut for all Floci calls:
```bash
alias awsfl="aws --endpoint-url http://localhost:4566 --region us-east-1"
```

---

## Service 1 — SES (Transactional Email)

**What it does**: sends portal emails — invitations, password resets, TOTP setup,
compliance notifications. Currently bypassed with SKIP_MFA because email never arrives.

**Why first**: unblocks testing real portal flows without the SKIP_MFA crutch.

### Implementation (Floci)

Configure the portal mailer in `config/environments/production.rb` (the Docker env uses
production mode):

```ruby
config.action_mailer.delivery_method = :smtp
config.action_mailer.smtp_settings = {
  address:              ENV.fetch("SES_SMTP_HOST", "localhost"),
  port:                 ENV.fetch("SES_SMTP_PORT", "1025").to_i,
  enable_starttls_auto: false,
  authentication:       nil
}
config.action_mailer.default_url_options = {
  host: ENV.fetch("APP_HOST", "localhost"),
  port: ENV.fetch("APP_PORT", "3000")
}
```

Add to `docker-compose.yml` under `yagye_portal` environment:
```yaml
SES_SMTP_HOST: floci
SES_SMTP_PORT: "1025"      # Floci SES SMTP port
APP_HOST: localhost
APP_PORT: "3000"
```

Verify a sender identity first (SES requires this even locally):
```bash
awsfl ses verify-email-identity --email-address noreply@yagye.com
```

### Verification steps

1. Trigger a portal password reset email
2. Open Floci UI → SES Mailbox → confirm email arrived
3. Check subject line, links resolve, no broken assets

### What to watch for (local)

- Floci SES stores emails in its mailbox UI, it does not actually send them to real addresses
- Always verify sender identity before sending or SES rejects the call
- Check `FROM` address matches the verified identity

### Real AWS transition

1. Verify sender domain in AWS SES console (adds DNS TXT records)
2. Request production access (SES starts in sandbox — can only send to verified addresses)
3. Set `SES_SMTP_HOST` to `email-smtp.<region>.amazonaws.com` and use IAM SMTP credentials
4. **Watch out**: SES sandbox limits to 200 emails/day and verified addresses only. Request
   production access before launch. Processing time is 24–48 hours.

---

## Service 2 — Secrets Manager

**What it does**: stores secrets (DB passwords, PSP API keys, encryption keys) outside
the app — no secrets in environment variables or code.

**Why second**: once working, all subsequent services store their credentials here
rather than in docker-compose environment blocks.

### Implementation (Floci)

Create secrets:
```bash
# Core DB password
awsfl secretsmanager create-secret \
  --name yagye/core/db_password \
  --secret-string "your-db-password"

# PSP provider credentials
awsfl secretsmanager create-secret \
  --name yagye/core/mtn_api_key \
  --secret-string '{"api_key":"test-key","api_secret":"test-secret"}'
```

Retrieve in Elixir (add `ex_aws_secretsmanager` to mix.exs):
```elixir
{:ok, %{"SecretString" => secret}} =
  ExAws.SecretsManager.get_secret_value("yagye/core/db_password")
  |> ExAws.request()
```

### Verification steps

```bash
awsfl secretsmanager list-secrets
awsfl secretsmanager get-secret-value --secret-id yagye/core/db_password
```

### What to watch for (local)

- Secret names are case-sensitive and use path notation (`yagye/core/name`)
- Floci does not enforce IAM policies; real AWS will reject calls without the right policy
- Write down the IAM policy you need as you go — apply it at P22

### Real AWS transition

- Write IAM policy granting `secretsmanager:GetSecretValue` for `arn:aws:secretsmanager:*:*:secret:yagye/*`
- Attach policy to the EC2 instance role (not hardcoded credentials)
- Remove secrets from docker-compose env block — apps fetch them at startup
- **Watch out**: secret rotation in AWS costs $0.05/secret/month. Plan your secret
  naming scheme before P22 — renaming secrets means updating all app references.

---

## Service 3 — Parameter Store

**What it does**: stores non-secret configuration — feature flags, rate limits, tier
thresholds, MoMo velocity caps — that ops can change without redeploying.

**Why third**: cheaper than Secrets Manager ($0 for standard parameters vs $0.05/secret),
and the right tool for config that isn't a credential.

### Implementation (Floci)

```bash
# KYC tier velocity limits
awsfl ssm put-parameter \
  --name /yagye/core/kyc_tier1_daily_limit \
  --value "1000" \
  --type String

# Feature flags
awsfl ssm put-parameter \
  --name /yagye/core/feature_escrow_enabled \
  --value "true" \
  --type String
```

Retrieve in Elixir:
```elixir
{:ok, %{"Parameter" => %{"Value" => value}}} =
  ExAws.SSM.get_parameter("/yagye/core/kyc_tier1_daily_limit")
  |> ExAws.request()
```

### Verification steps

```bash
awsfl ssm get-parameters-by-path --path /yagye/core --recursive
```

### Real AWS transition

- Use `SecureString` type for anything sensitive (encrypted with KMS automatically)
- Advanced parameters (> 10,000 params or > 4KB value) cost $0.05/param/month; stay on Standard
- **Watch out**: parameter names are global per AWS account+region. Use a prefix
  (`/yagye/<env>/<service>/name`) from day one so staging and prod don't collide.

---

## Service 4 — S3 (Object Storage)

**What it does**: stores KYB documents (P21) and the data lake (Bronze/Silver/Gold
Parquet files, P19 onwards). Already partially wired via Floci in docker-compose.

### Bucket structure for Yagye

```
yagye-kyb-documents/          ← encrypted KYB uploads (P21)
  merchants/<merchant_code>/
    <doc_id>/<filename>

yagye-lake-bronze/            ← raw NDJSON event stream (P19)
  events/dt=YYYY-MM-DD/

yagye-lake-silver/            ← cleaned Parquet by domain (P19)
  payments/dt=YYYY-MM-DD/

yagye-lake-gold/              ← aggregated analytics (P19)
  provider_health_hourly/dt=YYYY-MM-DD/
```

### Create buckets in Floci

```bash
awsfl s3 mb s3://yagye-kyb-documents
awsfl s3 mb s3://yagye-lake-bronze
awsfl s3 mb s3://yagye-lake-silver
awsfl s3 mb s3://yagye-lake-gold
```

There is a mix task for this already: `mix yagye.s3.setup`.

### Verification steps

```bash
# Upload a test object
awsfl s3 cp /tmp/test.txt s3://yagye-kyb-documents/test.txt

# List objects
awsfl s3 ls s3://yagye-kyb-documents/

# Generate a presigned URL (5 min expiry)
awsfl s3 presign s3://yagye-kyb-documents/test.txt --expires-in 300
```

Verify DuckDB can read from Floci S3:
```python
import duckdb
con = duckdb.connect()
con.execute("INSTALL httpfs; LOAD httpfs;")
con.execute("""
  CREATE SECRET (
    TYPE s3,
    KEY_ID 'test', SECRET 'test',
    ENDPOINT 'localhost:4566', USE_SSL false, URL_STYLE 'path'
  )
""")
con.execute("SELECT * FROM read_parquet('s3://yagye-lake-gold/provider_health_hourly/*/*.parquet')")
```

### What to watch for (local)

- Floci S3 uses path-style URLs (`http://localhost:4566/bucket/key`), not virtual-hosted style
  (`http://bucket.localhost:4566/key`). Real AWS uses virtual-hosted by default. Set
  `AWS_S3_FORCE_PATH_STYLE=true` in Floci envs (already done) and remove it at P22.
- Large presigned URLs must be generated server-side — never expose credentials to the browser
- Keep one object per document version; never overwrite — append with a new key

### Real AWS transition

- Enable bucket versioning on `yagye-kyb-documents` (compliance requirement for KYB docs)
- Enable server-side encryption (SSE-S3 minimum; SSE-KMS for KYB — see Service 5)
- Block all public access on every bucket
- Use VPC Gateway Endpoint for S3 so traffic stays inside AWS (free, avoids data transfer costs)
- **Watch out**: S3 bucket names are globally unique. `yagye-kyb-documents` may already be taken.
  Use a suffix: `yagye-kyb-documents-<account-id-last-4>`.

---

## Service 5 — KMS (Encryption)

**What it does**: manages encryption keys for KYB documents. S3 alone does
server-side encryption with AWS-managed keys; KMS gives you customer-managed keys
(CMKs) so you control rotation and audit every access.

**Why after S3**: KMS keys are referenced by S3 bucket encryption config.

### Implementation (Floci)

```bash
# Create a CMK for KYB documents
awsfl kms create-key \
  --description "Yagye KYB document encryption" \
  --key-usage ENCRYPT_DECRYPT

# Note the KeyId from the output, then create an alias
awsfl kms create-alias \
  --alias-name alias/yagye-kyb \
  --target-key-id <KeyId>
```

Configure S3 bucket default encryption:
```bash
awsfl s3api put-bucket-encryption \
  --bucket yagye-kyb-documents \
  --server-side-encryption-configuration '{
    "Rules": [{
      "ApplyServerSideEncryptionByDefault": {
        "SSEAlgorithm": "aws:kms",
        "KMSMasterKeyID": "alias/yagye-kyb"
      }
    }]
  }'
```

### Verification steps

```bash
# Encrypt a string directly
awsfl kms encrypt \
  --key-id alias/yagye-kyb \
  --plaintext "test-document-content"

# Verify bucket uses KMS
awsfl s3api get-bucket-encryption --bucket yagye-kyb-documents
```

### What to watch for (local)

- KMS costs $1/CMK/month on real AWS. Use one key per sensitivity level, not one per merchant.
- KMS calls are audited in CloudTrail — every encrypt/decrypt shows who accessed what document
- Never hardcode the key ARN; use `alias/yagye-kyb` so you can rotate the underlying key

### Real AWS transition

- Enable automatic key rotation (annual) — KMS rotates the backing material but keeps the alias
- Write a key policy granting `kms:GenerateDataKey` and `kms:Decrypt` to your EC2 role
- **Watch out**: if you delete a CMK, all data encrypted with it becomes permanently
  unreadable. Enable key deletion protection and require a 30-day waiting period.

---

## Service 6 — EventBridge (Scheduled Jobs)

**What it does**: replaces the `while true; sleep 3600` cron pattern used in
`yagye_data` for data lake ingestion. Triggers Lambda or an HTTP endpoint on a schedule.

**Why here**: the data pipeline (P19) benefits from reliable scheduling. EventBridge
Scheduler survives container restarts — a sleep loop does not.

### Implementation (Floci)

```bash
# Create a rule that fires every hour
awsfl events put-rule \
  --name yagye-data-lake-hourly \
  --schedule-expression "rate(1 hour)" \
  --state ENABLED

# Point it at your data worker endpoint
awsfl events put-targets \
  --rule yagye-data-lake-hourly \
  --targets '[{
    "Id": "data-lake-trigger",
    "Arn": "arn:aws:sqs:us-east-1:000000000000:yagye-data-jobs",
    "Input": "{\"job\":\"DataLakeIngestionWorker\"}"
  }]'
```

### Verification steps

```bash
awsfl events list-rules
awsfl events list-targets-by-rule --rule yagye-data-lake-hourly
```

Check CloudWatch Events metrics to confirm rule is firing.

### What to watch for (local)

- EventBridge in Floci fires rules but the target must be reachable within Docker networking
- Use SQS as an EventBridge target (not an HTTP endpoint) for reliability — the worker
  polls the queue rather than EventBridge calling it directly
- Floci's Cloud Scheduler UI is Coming Soon; use EventBridge API directly for now

### Real AWS transition

- Minimum EventBridge rule interval is 1 minute
- EventBridge Scheduler (not classic EventBridge rules) supports one-time and timezone-aware
  schedules — use it for settlement batch windows and compliance deadlines
- **Watch out**: if the target SQS queue or Lambda doesn't exist, EventBridge silently
  drops the event. Add a DLQ to the target and monitor it.

---

## Service 7 — SQS (Dead Letter Queues)

**What it does**: catches events that fail to process — webhook delivery failures,
EventBridge missed targets — so they can be retried or inspected without data loss.

**Why here**: once EventBridge and SES are live, you need somewhere safe for failed
deliveries to land. Oban handles internal job retries; SQS handles external webhook DLQs.

### Implementation (Floci)

```bash
# Create the DLQ first
awsfl sqs create-queue --queue-name yagye-webhooks-dlq

# Create the main queue with the DLQ attached
awsfl sqs create-queue \
  --queue-name yagye-webhooks \
  --attributes '{
    "RedrivePolicy": "{\"deadLetterTargetArn\":\"arn:aws:sqs:us-east-1:000000000000:yagye-webhooks-dlq\",\"maxReceiveCount\":\"5\"}"
  }'
```

### Verification steps

```bash
awsfl sqs list-queues
awsfl sqs get-queue-attributes \
  --queue-url http://localhost:4566/000000000000/yagye-webhooks \
  --attribute-names All
```

Send a test message and confirm it arrives in the DLQ after 5 failures:
```bash
awsfl sqs send-message \
  --queue-url http://localhost:4566/000000000000/yagye-webhooks \
  --message-body '{"test":true}'
```

### What to watch for (local)

- SQS message visibility timeout must be longer than your longest webhook retry cycle
- FIFO queues (`.fifo` suffix) guarantee order and exactly-once delivery — use for
  financial events that must not be processed twice
- Standard queues can deliver a message more than once — always make webhook handlers idempotent

### Real AWS transition

- SQS is permanently free up to 1 million requests/month (per the article, this is accurate)
- Long polling (`ReceiveMessage` with `WaitTimeSeconds=20`) is free and reduces empty receives
- **Watch out**: SQS message retention is 4 days by default, max 14 days. Set to 14 days
  for a PSP DLQ so you don't lose failed webhook events over weekends.

---

## Observability — Assessment & Gaps

### Current stack verdict: correct choice

Your LGTM stack (Loki + Grafana + Tempo + Prometheus + Alloy) is what Grafana, GitLab,
Shopify, and most PSPs use. It is production-grade, fully open-source, runs identically
in Docker Compose and on EC2, and has a managed cloud option (Grafana Cloud) for P22
with a generous free tier (10 GB logs, 50 GB metrics, 50 GB traces). Do not switch to
CloudWatch + X-Ray — it is more expensive, less flexible, and locks you to AWS.

**Do not use Fluentbit**. Grafana Alloy replaces it entirely for this stack. Alloy
collects logs, metrics, and traces in one process and ships to Loki, Prometheus, and
Tempo natively. Fluentbit would be the right choice only if you were on ECS Fargate
(which has a Fluentbit sidecar built in), which you are not.

### Three gaps to fix before P22

#### Gap 1 — Alertmanager ✓ Fixed

Added to docker-compose: `alertmanager` (port 9093) + `mailpit` (SMTP :1025, UI :8025).
`prometheus.yml` now targets `alertmanager:9093`. Loki's `alertmanager_url` updated to
`http://alertmanager:9093`. Config at `infra/docker/alertmanager/config.yml`.

Alert emails go to `ops@yagye.com` via Mailpit in dev (view at http://localhost:8025).
Production: replace `mailpit:1025` with `email-smtp.<region>.amazonaws.com:587` and
set SES SMTP credentials from Secrets Manager.

Minimum alert channels:
- Warning → email ops@yagye.com (4 h repeat)
- Critical → email ops@yagye.com (1 h repeat, subject tagged `[CRITICAL]`)
- Inhibit rules suppress warning when critical fires for same alert+team

#### Gap 2 — Node Exporter + cAdvisor ✓ Fixed

Added `node_exporter` (port 9100) and `cadvisor` (port 8080) to docker-compose.
Alloy config now scrapes both and forwards to Prometheus.

The existing disk/CPU/RAM alert rules in `alerts.yml` now have real data to evaluate.

**On EC2 at P22**: run Node Exporter as a systemd service on the host (not in Docker)
so it survives Docker daemon restarts.

#### Gap 3 — Traces disabled in dev ✓ Fixed

Added to `runtime.exs`:
```elixir
if System.get_env("OTEL_TRACES_ENABLED") == "true" do
  config :opentelemetry, traces_exporter: :otlp
end
```

`runtime.exs` runs at app startup and overrides the compiled `dev.exs` `:none` setting.
Added `OTEL_TRACES_ENABLED: "true"` to `yagye_core` in docker-compose. Portal already
had `OTEL_TRACES_EXPORTER: otlp` via env var — no change needed there.

Running natively (without Docker): `OTEL_TRACES_ENABLED` is unset, so traces are still
dropped and there is no noise from a missing Alloy endpoint.

### Trace propagation across services

For end-to-end traces (Portal → Core → Oban workers → DB), every HTTP call between
services must propagate the W3C TraceContext header (`traceparent`).

Core: `opentelemetry_req` already instruments `Req` HTTP calls — it adds `traceparent`
automatically to outgoing requests.

Portal: `opentelemetry-instrumentation-all` instruments Faraday/Net::HTTP outgoing
calls automatically.

**Verify it works**: make a payment from the portal, then in Grafana → Tempo search for
the trace. You should see spans from `yagye_portal` and `yagye_core` stitched together
in one waterfall, with Ecto query spans under the Core spans.

### On AWS at P22

Three options for where your LGTM stack runs:

| Option | Cost | Effort | Recommended |
|---|---|---|---|
| Grafana Cloud free tier | Free up to limits | Minimal — just change endpoints | **Yes, start here** |
| Self-hosted on t3.small | ~$15/month | Medium — manage the EC2 | Later, if you exceed free tier |
| AWS CloudWatch + X-Ray | Variable, often more expensive | High — different query language | No |

Grafana Cloud free tier gives you 14-day retention, 10 GB logs, 50 GB metrics, and 50 GB
traces — enough for all of P22 testing. The only change is pointing Alloy's remote_write
and loki.write endpoints at Grafana Cloud URLs instead of your local services.

---

## End-to-end verification checklist

After all services are implemented, run through this in order:

- [ ] Portal sends a user invitation → email arrives in Floci SES Mailbox
- [ ] Portal fetches a secret from Secrets Manager on startup (verify in app logs)
- [ ] A KYB document upload → file appears in `s3://yagye-kyb-documents/` with KMS encryption
- [ ] Presigned URL for a KYB document resolves and downloads the file
- [ ] EventBridge rule fires on schedule → data lake ingestion job runs
- [ ] A failed webhook delivery → message lands in SQS DLQ after 5 retries
- [ ] Prometheus alert fires → notification arrives in Slack (Alertmanager wired)
- [ ] Node Exporter metrics appear in Grafana — disk, CPU, RAM graphs populated
- [ ] A payment trace shows Core + Portal spans stitched in Tempo

---

## Real AWS transition checklist (P22)

When you move from Floci to real AWS, for each service:

1. **Remove endpoint overrides** — delete `AWS_S3_HOST`, `AWS_S3_PORT`, `S3_ENDPOINT_URL`,
   etc. from docker-compose and ECS task definitions. `ex_aws` and boto3 default to real AWS.
2. **Switch credentials** — replace `test`/`test` with an IAM Role attached to EC2/ECS.
   Never hardcode AWS credentials in code or environment variables on real AWS.
3. **Apply IAM policies** — write the minimum policy for each service (listed above under
   each service's "Real AWS transition" section).
4. **Set a billing alarm** — $20 threshold, email you. Do this before anything else.
5. **Same region** — put EC2, RDS, S3, and all services in the same region to avoid
   cross-region data transfer charges (free inside one region, billed otherwise).
6. **VPC Gateway Endpoints** — add free Gateway Endpoints for S3 and DynamoDB so traffic
   stays inside AWS and does not leave through a NAT Gateway.

### Cost estimate for Yagye at P22 (testing phase)

| Service | Type | Est. cost/month |
|---|---|---|
| EC2 t3.medium (PSP + Portal) | On-demand | ~$30 |
| RDS db.t3.micro PostgreSQL Single-AZ | On-demand | ~$15 |
| S3 (< 10 GB) | Storage + requests | < $1 |
| SES (< 1,000 emails) | Per email | < $0.10 |
| KMS (1 CMK) | Per key | $1 |
| EventBridge (< 1M events) | Free tier | $0 |
| SQS (< 1M requests) | Free tier | $0 |
| Secrets Manager (5 secrets) | Per secret | $0.25 |
| Grafana Cloud | Free tier | $0 |
| **Total** | | **~$47–50/month** |

No NAT Gateway, no ALB (use Caddy on EC2 directly), no Multi-AZ, no managed MSK —
run Redpanda as a container on the same EC2 instance.
