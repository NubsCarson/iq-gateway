# Gateway recovery: Akash and Cloudflare handoff for Zo

Live checks refreshed 2026-09-19 04:34 UTC (September 18, Pacific). This handoff covers the gateway only. No ownership transfer or access grants have been made.

## Note for Zo

We recovered access to the original computer, wallets, and Cloudflare account and restored the gateway at https://gateway.solanainternet.com. The Akash deployment is running and received an additional 90 days of funding.

We can leave the frontend wherever and however you are hosting it now to keep this simple. There is also recovered Arweave frontend work and optional Solana hosting research. Would you like more information about either, or should we keep the scope to the gateway? No frontend hosting change is required for this handoff.

## Gateway status and verification

- Endpoint: https://gateway.solanainternet.com
- Fresh health check: HTTP 200 with status ok on /health; a representative table read returned HTTP 200 and 1 rows. Gateway local tests previously passed 114 tests. Health reported 225 RPC calls, 1 cumulative error, zero rate-limit events, and no queued requests at this check.
- Source commit: IQCoreTeam/iq-gateway at 25427b3f50a4d0f8db365b6be0eb029358d1cda2.
- Container image: ghcr.io/iqcoreteam/iq-gateway@sha256:7fce271cf560ebfd3760e966c174674816cbe47deca2f63ec5b44f0a121e1a5b
- This deployment currently serves Solana gateway requests; EVM backends are not configured.
- Production uses exactly one Helius RPC key through SOLANA_RPC_ENDPOINT. The owner identifies it as a free-plan key; the provider billing tier has not been independently verified. There is no configured RPC-key rotation, and the optional Helius batch API is disabled. The credential is private and is not included here or in the template.

## Akash deployment and funding

| Item | Value |
|---|---|
| Deployment DSEQ | 28688125 |
| Owner / funding address | akash1yz0080hzn89vny5qwx845ttanvqfeefhv6wv80 |
| Provider | akash1hgulk6aekakqzc0v6wukrd3dy9n90f5gkl4ezk |
| Resources | 4 CPU, 4 GiB RAM, 1 GiB ephemeral storage, 10 GiB persistent NVMe cache |
| Actual lease rate | 18 uACT per block |
| Estimated running cost | 0.2592 ACT/day or 7.776 ACT per 30 days, assuming 6-second blocks |
| Escrow funding | Initial 10 ACT plus confirmed 23.328 ACT top-up |

The deployment and lease are both active. Escrow reports 33.328 ACT at settlement height 28688143. Deducting accrued rent through observed block 28689859 gives approximately 33.297112 ACT, or 128.5 days at 6-second blocks. This is a calculated estimate, not a guaranteed expiry date. The added 23.328 ACT corresponds to approximately 90 days at that block-time assumption.

Confirmed top-up transaction: 0E0BBD54E841CE34E85DC28C25C048EC846D901A78979B66CF9A2E69C40BC9D6, height 28688432.

Owner-wallet balance freshly rechecked: 53.791103 AKT and 0.169236 ACT. These values are snapshots as of the check above. Sending AKT to the owner wallet does not itself extend hosting: obtain ACT and deposit it into this deployment's escrow. Recheck live balances, conversion quote, lease price, and escrow before spending.

The accompanying akash-recovery.template.yaml is a redacted configuration reference. It includes a bid ceiling from preparation, not the actual accepted lease price above. Supply the RPC endpoint privately and inspect the current deployment before applying anything. Do not create a duplicate or close the working lease just to take over operations.

## Cloudflare DNS

- Domain: solanainternet.com, in the recovered Cloudflare account.
- Zone ID: 68ee03df8522c68b60a2500a585236da.
- Record: gateway CNAME to mv0rj8i5bl81h97nevfvj5i2f8.ingress.h4i-dedicated.eu-sw-2.digitalfrontier.so.
- Proxy: enabled. SSL/TLS mode: Full. Both were rechecked in the Cloudflare dashboard for this review.
- Preserve existing MX, SPF, and DKIM records.
- Apex and www website routing are outside this gateway handoff.

If a future deployment gets a new provider hostname, verify the replacement endpoint first, update this CNAME, then check HTTPS health and representative reads through gateway.solanainternet.com. Record the old target so DNS can be restored if needed.

## Proposed operator access — decide with Zo

First agree which duties Zo wants: gateway updates, funding, DNS maintenance, or some subset. Obtain her verified email and Akash public address, plus agreed spending limits and access duration. No private keys are needed to discuss or prepare this plan.

- Akash: investigate permissions for Zo's own wallet using expiring Authz and a limited fee allowance. Verify the supported message versions and provider certificate/manifest requirements before promising that delegated access covers every operation. Agree separately on authority to close deployments, create new ones, or spend funds.
- Cloudflare: grant access limited to this domain and the required DNS operations where supported. Avoid unrelated domain, account, and billing permissions.
- RPC: agree who owns the provider account, quota, billing, and credential rotation. Deliver any required credential privately. Never place it in the fork, PR, document, or public SDL.

Keep ownership with the current owner unless a separate transfer is explicitly agreed. No access invitation or message to Zo has been sent.

## Laptop agent and fork/PR preparation

1. Confirm the intended gateway fork and branch with the owner. This package is local preparation; no GitHub push, issue edit, or PR has been made.
2. Recheck the gateway health, representative reads, deployment status, escrow, and DNS. Treat the recorded balances and runtime estimate as snapshots.
3. Place this document and the redacted SDL in the agreed gateway repository's operations documentation. Review for credentials before committing or pushing.
4. Prepare a gateway-only PR describing the restored service, funding, DNS, operational checks, and proposed access. Keep frontend changes and hosting research separate.
5. Ask Zo which gateway responsibilities she wants, then prepare the exact permissions for owner approval. Do not grant access or transfer ownership based solely on this plan.

After any gateway update, verify /health, representative table reads, provider logs, and remaining escrow. Retain the known image digest and previous DNS target for rollback planning.

