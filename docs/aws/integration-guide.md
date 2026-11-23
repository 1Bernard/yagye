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

---

## P22 Networking — VPC, Subnets, Security Groups

**No Floci equivalent.** VPC constructs exist in LocalStack but are unenforced no-ops —
Docker handles local isolation. Build this in real AWS first, before provisioning any other
service. Everything else (EC2, RDS, S3 Gateway Endpoint) depends on the VPC being in place.

### Architecture

```
VPC: 10.0.0.0/16  (us-east-1, single region — all services in same region)

  Public subnet:  10.0.1.0/24  (us-east-1a)
    └── EC2 t3.medium (Caddy + all Docker containers: Core, Portal, Redpanda,
                       Redis, Prometheus, Loki, Tempo, Grafana, Oban)

  Private subnet: 10.0.2.0/24  (us-east-1a)
    └── RDS db.t3.micro PostgreSQL (Single-AZ)

Internet Gateway → attached to VPC → route 0.0.0.0/0 from public subnet

No NAT Gateway   — RDS is private and needs no outbound internet
No ALB           — Caddy on EC2 handles TLS termination (port 80/443)
                   Revisit ALB when you need WAF or multi-instance
```

### Security groups

```hcl
# ec2-sg: the instance running all containers
resource "aws_security_group" "ec2" {
  name   = "yagye-ec2"
  vpc_id = aws_vpc.main.id

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP redirect (Caddy redirects to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "SSH from your IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["<YOUR_IP>/32"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# rds-sg: PostgreSQL — reachable only from EC2, never from internet
resource "aws_security_group" "rds" {
  name   = "yagye-rds"
  vpc_id = aws_vpc.main.id

  ingress {
    description     = "Postgres from EC2 only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
  }
}
```

### Terraform — full VPC block

```hcl
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = { Name = "yagye-vpc" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = { Name = "yagye-public" }
}

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "yagye-private" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# S3 Gateway Endpoint — free, keeps S3 traffic inside AWS (no data transfer charge)
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.public.id]
}
```

### What to verify after provisioning

```bash
# Confirm EC2 is reachable
curl -I https://portal.yagye.com   # should return 200

# Confirm RDS is NOT reachable from your laptop directly (should time out)
psql -h <rds-endpoint> -U yagye -d yagye_core_production   # must time out

# Confirm RDS IS reachable from EC2
ssh ec2-user@<ec2-ip>
psql -h <rds-endpoint> -U yagye -d yagye_core_production   # must connect

# Confirm S3 traffic uses the Gateway Endpoint (no charge)
# In VPC Flow Logs, S3 traffic should show destination as the endpoint, not 0.0.0.0
```

### When to add ALB

Add an Application Load Balancer when any of these is true:
- You need AWS WAF (web application firewall) in front of Portal
- You are running more than one EC2 instance and need load balancing
- You need a fixed DNS name that survives EC2 replacement without updating DNS

At that point: provision `aws_lb` → target group → listener (443 with ACM cert) → update Caddy to listen on 8080 internally only. Estimated cost: +$18/month for ALB.

---

## IAM Policy Reference

Minimum policies needed at P22, consolidated in one place. Attach all to a single
EC2 instance profile role (never use hardcoded credentials).

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SecretsManager",
      "Effect": "Allow",
      "Action": ["secretsmanager:GetSecretValue"],
      "Resource": "arn:aws:secretsmanager:us-east-1:*:secret:yagye/*"
    },
    {
      "Sid": "ParameterStore",
      "Effect": "Allow",
      "Action": ["ssm:GetParameter", "ssm:GetParametersByPath"],
      "Resource": "arn:aws:ssm:us-east-1:*:parameter/yagye/*"
    },
    {
      "Sid": "S3DataLake",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:ListBucket", "s3:DeleteObject"],
      "Resource": [
        "arn:aws:s3:::yagye-lake-bronze",
        "arn:aws:s3:::yagye-lake-bronze/*",
        "arn:aws:s3:::yagye-lake-silver",
        "arn:aws:s3:::yagye-lake-silver/*",
        "arn:aws:s3:::yagye-lake-gold",
        "arn:aws:s3:::yagye-lake-gold/*"
      ]
    },
    {
      "Sid": "S3KybDocuments",
      "Effect": "Allow",
      "Action": ["s3:GetObject", "s3:PutObject", "s3:ListBucket"],
      "Resource": [
        "arn:aws:s3:::yagye-kyb-documents-<account-last-4>",
        "arn:aws:s3:::yagye-kyb-documents-<account-last-4>/*"
      ]
    },
    {
      "Sid": "KmsKyb",
      "Effect": "Allow",
      "Action": ["kms:GenerateDataKey", "kms:Decrypt"],
      "Resource": "arn:aws:kms:us-east-1:*:key/alias/yagye-kyb"
    },
    {
      "Sid": "SesSmtp",
      "Effect": "Allow",
      "Action": ["ses:SendEmail", "ses:SendRawEmail"],
      "Resource": "*",
      "Condition": {
        "StringEquals": {"ses:FromAddress": "noreply@yagye.com"}
      }
    },
    {
      "Sid": "EventBridgeDataLake",
      "Effect": "Allow",
      "Action": ["events:PutEvents"],
      "Resource": "arn:aws:events:us-east-1:*:event-bus/default"
    },
    {
      "Sid": "SqsWebhookDlq",
      "Effect": "Allow",
      "Action": [
        "sqs:SendMessage", "sqs:ReceiveMessage",
        "sqs:DeleteMessage", "sqs:GetQueueAttributes"
      ],
      "Resource": "arn:aws:sqs:us-east-1:*:yagye-webhooks*"
    }
  ]
}
```

---

## AWS Testing Phase — End-to-End Checklist

This is what to verify once you are on real AWS with the ~$47/month stack.
Work through it top to bottom. Each item calls out what is different from
Floci and what a failure tells you.

### Infrastructure (do these first)

- [ ] **Billing alarm set** — AWS Console → Billing → Budgets → $20 threshold → email alert.
  Do this before anything else. Misconfigured NAT Gateways can rack up $50/day silently.

- [ ] **EC2 reachable via HTTPS** — `curl -I https://portal.yagye.com` returns `200 OK`
  with Caddy TLS cert from Let's Encrypt. If 502: Caddy is up but Portal container
  is not. If connection refused: Caddy is not running or port 443 is not open in ec2-sg.

- [ ] **RDS unreachable from outside VPC** — `psql -h <rds-endpoint>` from your laptop
  times out after ~30 seconds. If it connects: rds-sg has 0.0.0.0/0 open — fix immediately.

- [ ] **EC2 → RDS connection works** — SSH into EC2, run
  `psql -h <rds-endpoint> -U yagye -d yagye_core_production -c '\l'`. If it fails:
  check rds-sg allows port 5432 from ec2-sg, and that RDS subnet route table has no
  conflicting rules.

### IAM and credentials

- [ ] **No hardcoded credentials in containers** — `docker exec yagye_core env | grep AWS`
  should show no `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`. The app must use the
  EC2 instance metadata service (IMDS) instead. If keys appear: remove from docker-compose
  and attach an instance profile role to the EC2 instead.

- [ ] **Instance profile has correct role** — `curl http://169.254.169.254/latest/meta-data/iam/info`
  from EC2 returns a role ARN. If empty: no instance profile is attached — go to EC2
  console → Actions → Security → Modify IAM Role.

### Service health (run after IAM verified)

- [ ] **Secrets Manager** — `aws secretsmanager get-secret-value --secret-id yagye/core/db_password`
  from EC2 (without `--endpoint-url`) returns the secret. If `AccessDenied`: the instance
  profile is missing `secretsmanager:GetSecretValue`. Check the IAM policy above.

- [ ] **Parameter Store** — `aws ssm get-parameters-by-path --path /yagye/core` from EC2
  returns parameters. If empty: parameters were not migrated from Floci — re-run the
  `awsfl ssm put-parameter` commands against real AWS.

- [ ] **SES email delivery** — trigger a portal password reset for a real email address
  (not a test address, since SES sandbox only allows verified addresses). Email arrives
  within 60 seconds. If it doesn't arrive: check SES console → Sending Statistics for
  bounces or rejections. If `MessageRejected`: sender domain not verified or still in sandbox.

- [ ] **S3 KYB upload** — upload a KYB test document through the portal. Confirm in
  AWS Console → S3 → `yagye-kyb-documents-<suffix>` that the object exists with
  `Server-side encryption: aws:kms` shown. If encryption is `AES-256` (SSE-S3 not SSE-KMS):
  the bucket default encryption is not set — re-run `s3api put-bucket-encryption`.

- [ ] **S3 presigned URL** — from the portal, generate a KYB document download link.
  Open the URL in a fresh browser tab (not logged in). It must resolve and return the
  file. If 403: the presigned URL was generated with Floci credentials — confirm the
  app is using IMDS credentials, not `AWS_ACCESS_KEY_ID=test`.

- [ ] **S3 Gateway Endpoint** — confirm S3 traffic does not leave the VPC. In VPC Flow
  Logs (enable temporarily if not on): S3 destination IPs should be in the AWS-owned
  prefix, not routed through the internet gateway. Alternatively: remove the EC2's public
  route and confirm S3 still works (the Gateway Endpoint does not need a default route).

- [ ] **Data lake write** — trigger `DataLakeIngestionWorker` manually:
  `mix run -e "YagyeCore.DataLake.Workers.DataLakeIngestionWorker.perform(%Oban.Job{})"`.
  Confirm an NDJSON object appears in `s3://yagye-lake-bronze/events/dt=<today>/`.
  If `AccessDenied`: the instance profile is missing the S3 data lake policy.

- [ ] **EventBridge scheduling** — wait for the next scheduled EventBridge rule to fire
  (or manually trigger it via AWS Console → EventBridge → Rules → Send test event).
  Confirm a data lake ingestion job runs and a new object lands in Bronze S3.
  If nothing happens: check the EventBridge target SQS queue for messages stuck in DLQ.

- [ ] **SQS DLQ** — send a webhook to a deliberately broken endpoint 5 times. Check
  `yagye-webhooks-dlq` queue depth increases by 1. If the message disappears without
  going to DLQ: the `maxReceiveCount` or DLQ ARN in the redrive policy is wrong.

### Observability (run last — depends on all services being up)

- [ ] **Alloy → Grafana Cloud** — Alloy config uses real Grafana Cloud endpoints
  (not `loki:3100`/`tempo:4317`). Open Grafana Cloud → Explore → Loki, query
  `{service_name="yagye_core"}`. Logs from the last 5 minutes should appear.
  If empty: check Alloy logs on EC2 (`docker logs yagye_alloy`) for auth errors.

- [ ] **Full distributed trace** — make a payment through the portal. In Grafana Cloud
  → Tempo → Search, query `service.name = yagye_portal`. Find the trace and confirm
  it shows spans from both `yagye_portal` and `yagye_core` in a single waterfall.
  If Core spans are missing: `traceparent` header propagation is broken between Portal
  → Core — check `CoreApiClient` injects the header.

- [ ] **Prometheus alert firing** — temporarily set the `DiskUsedPercent > 80` alert
  threshold to `> 1` in `alerts.yml` and reload Prometheus. Confirm Alertmanager
  sends an email to `ops@yagye.com` via SES (not Mailpit — that is Floci only).
  Revert the threshold after confirming. If email does not arrive: Alertmanager
  is still pointed at `mailpit:1025` — update to SES SMTP endpoint.

- [ ] **AI chat (Portal)** — open the AI Assistant panel in the portal as a merchant.
  Send a message. Response streams back within 5 seconds. Check Langfuse dashboard
  for the LLM call trace. If 500 error: `ANTHROPIC_API_KEY` is not set in the
  Portal container env — add it to Secrets Manager and fetch at startup.

### Sign-off criteria

All items above checked. No hardcoded credentials. No 0.0.0.0/0 on rds-sg.
Billing alarm confirmed active. At this point the stack is ready for the first
real merchant onboarding test.
