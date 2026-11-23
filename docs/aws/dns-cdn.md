# DNS, CDN, and Subdomain Architecture — Yagye

You own `yagye.com` on Namecheap. You do not need to buy additional domains.
Subdomains are free and unlimited. This document covers the subdomain layout,
DNS strategy, and CDN decision — including what changes at each phase.

---

## Subdomain map

| Subdomain | Service | Audience |
|---|---|---|
| `yagye.com` | Marketing page (static) | Public |
| `www.yagye.com` | Redirect → `yagye.com` | Public |
| `portal.yagye.com` | Merchant dashboard (Rails portal) | Merchants + ops |
| `api.yagye.com` | Core PSP API (Elixir/Phoenix) | Merchants, integrators |
| `checkout.yagye.com` | Hosted checkout for customers | Customers |
| `docs.yagye.com` | Developer documentation | Integrators |
| `status.yagye.com` | Public status page (Uptime Kuma) | Everyone |
| `sim.yagye.com` | Simulator (sandbox mode only) | Developers |
| `grafana.yagye.com` | Grafana dashboards (internal) | Ops team (IP-restricted) |

All of these point to your single EC2 Elastic IP. Caddy routes by `Host` header
to the right Docker container port. You are not paying for nine servers —
you are paying for one EC2 and one domain.

**Cookie isolation**: keeping `portal.yagye.com` and `checkout.yagye.com` on
separate subdomains means browser cookies set by the portal cannot be read by
a checkout page and vice versa. This is not optional for a PSP — it is a
PCI-DSS scoping requirement. Never put the merchant dashboard and the
customer checkout on the same subdomain.

---

## DNS strategy — use Cloudflare (not Route 53)

**Recommended: move DNS from Namecheap to Cloudflare (free tier)**

Cloudflare is not just a DNS host — it is a reverse proxy, CDN, DDoS shield,
and WAF. For a PSP, the free tier gives you things that Route 53 cannot:

| Feature | Cloudflare Free | Route 53 | Namecheap DNS |
|---|---|---|---|
| DNS hosting | Free | $0.50/month | Free |
| Global CDN | Yes (300+ PoPs) | No | No |
| DDoS mitigation | Yes (always-on) | No | No |
| SSL/TLS to browser | Yes (auto) | No (need ACM + ALB) | No |
| Web Application Firewall | Basic rules free | No (pay-per-rule) | No |
| Cloudflare Turnstile (CAPTCHA) | Free | No | No |
| African PoPs (Ghana latency) | Yes (Accra, Lagos, Nairobi) | No | No |
| Analytics per subdomain | Yes | No | No |

For checkout pages specifically: Cloudflare's presence in West Africa (Accra PoP)
means your customers get a faster page load than if the request went all the way
to your EC2 in us-east-1. Static assets (JS, CSS, images) are cached at the
nearest PoP.

Turnstile is already wired into the portal auth views — it only works if you
are using Cloudflare DNS in proxy mode (the orange cloud).

### How to move DNS to Cloudflare (one-time, 5 minutes)

1. Create a free account at cloudflare.com → Add site → enter `yagye.com`
2. Cloudflare scans your existing Namecheap DNS records and imports them
3. Cloudflare gives you two nameservers, e.g.:
   ```
   ada.ns.cloudflare.com
   ben.ns.cloudflare.com
   ```
4. In Namecheap → Domain List → Manage → Nameservers → select
   "Custom DNS" → paste the two Cloudflare nameservers → Save
5. Propagation takes 5–30 minutes. Cloudflare's dashboard shows green when done.

After this, all DNS changes happen in Cloudflare — you never log into Namecheap
for DNS again. The domain registration stays on Namecheap; only DNS moves.

---

## DNS records to create in Cloudflare

After moving DNS, create these records. All A records point to your EC2
Elastic IP. The orange cloud icon (proxied) means Cloudflare sits in front;
the grey cloud (DNS only) means traffic goes direct to EC2.

| Type | Name | Value | Proxied | Notes |
|---|---|---|---|---|
| A | `@` | `<elastic-ip>` | Yes | yagye.com → EC2 via Cloudflare |
| CNAME | `www` | `yagye.com` | Yes | Redirect handled by Cloudflare |
| A | `portal` | `<elastic-ip>` | Yes | Merchant dashboard |
| A | `api` | `<elastic-ip>` | Yes | Core API |
| A | `checkout` | `<elastic-ip>` | Yes | Hosted checkout |
| A | `docs` | `<elastic-ip>` | Yes | Developer docs |
| A | `status` | `<elastic-ip>` | Yes | Status page |
| A | `sim` | `<elastic-ip>` | **No** | Simulator — DNS only, no Cloudflare proxy |
| A | `grafana` | `<elastic-ip>` | **No** | Grafana — DNS only + Caddy IP restriction |

**Why `sim` and `grafana` are grey (DNS only)**:
Cloudflare proxies traffic through its own IPs, which means your EC2 IP is
hidden. That is good for public subdomains but breaks your IP allowlist for
internal tools. Set these to DNS-only so you can restrict them by IP in Caddy
without Cloudflare's IPs defeating the allowlist.

### Caddy routing (on EC2)

```
yagye.com, www.yagye.com {
  redir https://yagye.com{uri} permanent
  root * /var/www/marketing
  file_server
}

portal.yagye.com {
  reverse_proxy localhost:3000
}

api.yagye.com {
  reverse_proxy localhost:4000
}

checkout.yagye.com {
  reverse_proxy localhost:4001   # or same 4000 with path routing
}

docs.yagye.com {
  root * /var/www/docs
  file_server
}

status.yagye.com {
  reverse_proxy localhost:3001   # Uptime Kuma
}

sim.yagye.com {
  reverse_proxy localhost:4002
}

grafana.yagye.com {
  @blocked not remote_ip <YOUR_IP>/32
  respond @blocked 403
  reverse_proxy localhost:3100
}
```

### SSL/TLS between Cloudflare and EC2

Set Cloudflare SSL/TLS mode to **Full (strict)** in the Cloudflare dashboard.

- **Flexible** (Cloudflare → HTTP → EC2): never use this. Caddy provides
  free Let's Encrypt certs anyway — there is no reason to run unencrypted
  between Cloudflare and your server.
- **Full**: Cloudflare → HTTPS → EC2 (self-signed cert accepted). Acceptable.
- **Full (strict)**: Cloudflare → HTTPS → EC2 (valid cert required). Use this.
  Caddy gets Let's Encrypt certs automatically — Full (strict) works out of
  the box.

---

## CDN strategy by phase

### P22 testing phase (now) — Cloudflare free tier

What Cloudflare caches for you automatically on the free tier:
- Static files served by Caddy: `.js`, `.css`, `.png`, `.jpg`, `.woff2`, etc.
- Marketing page assets
- Docs site assets

What Cloudflare does NOT cache (and should not):
- API responses from `api.yagye.com` — payment data must never be served from
  cache. Set `Cache-Control: no-store` on API responses.
- Portal pages — merchant-specific data, always pass-through.
- Checkout pages — session-specific, always pass-through.

Cloudflare Page Rules to add (free tier allows 3):

| URL pattern | Setting |
|---|---|
| `api.yagye.com/*` | Cache Level: Bypass |
| `portal.yagye.com/*` | Cache Level: Bypass |
| `checkout.yagye.com/*` | Cache Level: Bypass |

This ensures payment and merchant data is never accidentally served stale from
Cloudflare's cache.

### P23+ (scale phase) — upgrade options

Once you have real traffic, evaluate:

| Option | Cost | When to add |
|---|---|---|
| Cloudflare Pro | $20/month | When you need WAF custom rules or image optimisation |
| Cloudflare R2 | $0.015/GB/month | When static assets (docs, marketing) exceed free cache limits; cheaper than CloudFront + S3 |
| CloudFront + S3 | Variable | Only if you are already deep in AWS-native tooling; Cloudflare R2 is cheaper |
| Cloudflare Stream | $1/1,000 min | If you add video onboarding for merchants |

**Do not add CloudFront at P22.** It costs money and duplicates what Cloudflare
already does for free. Revisit at P23 if you need signed URLs for private S3
content that Cloudflare cannot reach (KYB documents) — but even then,
CloudFront signed URLs and S3 presigned URLs are both valid approaches.

---

## Elastic IP — required before DNS

Before creating any DNS records pointing to EC2, allocate an Elastic IP and
attach it to your instance. Without this, your EC2 public IP changes on every
reboot and your DNS breaks.

```bash
# Allocate an Elastic IP
aws ec2 allocate-address --domain vpc

# Note the AllocationId from output, then associate with your EC2
aws ec2 associate-address \
  --instance-id <your-ec2-instance-id> \
  --allocation-id <AllocationId>
```

Elastic IP is **free while attached to a running instance**. You pay $0.005/hour
(~$3.60/month) only if you allocate it but do not attach it. Never allocate
without attaching.

---

## Domain email (support@yagye.com)

You will need `noreply@yagye.com` for SES transactional email and optionally
`support@yagye.com` for merchant enquiries.

**Transactional email (SES)**:
1. In Cloudflare DNS, add the SES DKIM and SPF records that AWS gives you
   when you verify the domain in SES console (3 CNAME records + 1 TXT record)
2. Set `FROM: noreply@yagye.com` in Alertmanager and the Portal mailer
3. SES handles delivery — no mail server needed

**Support inbox (Cloudflare Email Routing — free)**:
1. In Cloudflare dashboard → Email → Email Routing → enable
2. Add a catch-all rule: `*@yagye.com` → forward to your personal Gmail
3. No MX records needed in Namecheap — Cloudflare sets them automatically
4. Free, unlimited forwarding addresses — `support@`, `alerts@`, `ops@` all
   forward to wherever you want without paying for Google Workspace

---

## End-to-end DNS verification checklist

After Cloudflare is live and DNS has propagated:

- [ ] `dig yagye.com` returns Cloudflare IPs (not your EC2 IP — that means proxy is on)
- [ ] `curl -I https://yagye.com` returns `200 OK` and `CF-RAY:` header is present
- [ ] `curl -I https://portal.yagye.com` returns `200 OK` from Rails portal
- [ ] `curl -I https://api.yagye.com/health` returns `200 OK` from Phoenix Core
- [ ] `curl -I https://api.yagye.com/payments` from Cloudflare Bypass cache rule returns
  `Cache-Control: no-store` header — payment endpoints must never be cached
- [ ] SSL Labs test at `ssllabs.com/ssltest/analyze.html?d=yagye.com` returns A or A+
  (Cloudflare handles TLS negotiation so this is free)
- [ ] Turnstile widget appears on `portal.yagye.com/sign_in` (only works when Cloudflare
  proxy is active and `CLOUDFLARE_TURNSTILE_SITE_KEY` env var is set)
- [ ] `support@yagye.com` test email arrives in your Gmail via Cloudflare Email Routing
- [ ] `noreply@yagye.com` SES test email delivers (check SES → Sending Statistics for
  bounces — SPF/DKIM must pass or SES goes to spam)
