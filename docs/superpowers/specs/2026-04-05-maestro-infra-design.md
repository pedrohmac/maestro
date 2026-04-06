# Maestro Infrastructure Design

## Overview

AWS infrastructure for Maestro's account-based subscription system. Provides user authentication (Cognito), subscription status storage (DynamoDB), and two API endpoints — one for the app to check subscription status, one for Lemon Squeezy webhooks.

**Repo:** `maestro-infra`, sibling to the main `maestro` repo.

**Region:** us-east-1

**Terraform state:** S3 backend with DynamoDB lock table, created by a bootstrap config.

---

## Project Structure

```
maestro-infra/
  bootstrap/                    # Run once: S3 bucket + DynamoDB lock for TF state
    main.tf
  terraform/
    main.tf                     # Provider, backend config
    cognito.tf                  # User pool, app client
    dynamodb.tf                 # Subscriptions table + GSI
    api_gateway.tf              # HTTP API, routes, JWT authorizer
    lambdas.tf                  # Both Lambda functions + IAM roles
    variables.tf                # Region, project name, LS webhook secret
    outputs.tf                  # User Pool ID, App Client ID, API URL
  lambdas/
    get_subscription/
      handler.py                # Reads DynamoDB by userId from JWT
    handle_webhook/
      handler.py                # Validates LS signature, upserts DynamoDB
  .gitignore
```

---

## Cognito User Pool

- **Sign-up:** Email/password only. Email is the username (no separate username field).
- **Email verification:** Required. Cognito sends a verification code automatically.
- **Password policy:** 8+ characters, requires uppercase + lowercase + number (Cognito defaults).
- **App client:** One client for the macOS app. Public client (no client secret) — standard for native apps.
- **No hosted UI** — the Maestro app has its own login/signup views that call Cognito SDK directly.
- **Token expiry:** ID token 1 hour, refresh token 30 days.

---

## DynamoDB Table

- **Table name:** `maestro-subscriptions`
- **Partition key:** `userId` (String) — the Cognito `sub` UUID
- **Billing:** On-demand (pay per request)

**Attributes:**

| Field | Type | Description |
|-------|------|-------------|
| `userId` | String | Cognito `sub` UUID (partition key) |
| `status` | String | `active`, `cancelled`, `past_due`, `expired` |
| `lemonSqueezyCustomerId` | String | Lemon Squeezy customer ID |
| `lemonSqueezySubscriptionId` | String | Lemon Squeezy subscription ID |
| `currentPeriodEnd` | String | ISO 8601 timestamp — when current billing period ends |
| `updatedAt` | String | ISO 8601 timestamp — last update |

**No GSI needed** — the webhook always receives `userId` via Lemon Squeezy custom checkout data, so all lookups are by partition key.

---

## API Gateway

- **Type:** HTTP API (cheaper and simpler than REST API)
- **No custom domain** — uses default `https://{id}.execute-api.us-east-1.amazonaws.com`
- **CORS:** Allow origin `*` for now (only the native app calls this, not a browser)

### Route 1: `GET /subscription` (authenticated)

- **Authorizer:** Cognito JWT authorizer — validates the ID token from the `Authorization: Bearer` header
- **Lambda:** `get-subscription`
- **Logic:**
  1. Extract `userId` from JWT claims (`sub`)
  2. Read DynamoDB by `userId` (simple `GetItem`)
  3. If found: return `{ status, currentPeriodEnd }`
  4. If not found: return `{ status: "none" }`

### Route 2: `POST /webhook/lemonsqueezy` (public)

- **No auth** — Lemon Squeezy cannot attach JWTs
- **Lambda:** `handle-webhook`
- **Logic:**
  1. Validate request using Lemon Squeezy webhook signing secret (HMAC-SHA256 of the raw body against the `X-Signature` header)
  2. Reject if signature invalid (return 401)
  3. Parse event type from payload
  4. Handle events: `subscription_created`, `subscription_updated`, `subscription_cancelled`, `subscription_expired`
  5. Extract `userId` from `custom_data.user_id` in the payload (passed via checkout URL)
  6. Extract subscription ID, customer ID, status, current period end from payload
  7. Upsert DynamoDB record by `userId` with new status, period end, timestamps
  8. Return 200

**How userId reaches the webhook:** The Maestro app opens the Lemon Squeezy checkout URL with `?checkout[custom][user_id]={cognitoSub}`. Lemon Squeezy passes this custom data through to all webhook events for that subscription. This requires the user to have a Cognito account before subscribing, which is enforced by the app flow (sign up → then subscribe).

---

## Lambda Functions

- **Runtime:** Python 3.12
- **Architecture:** arm64 (Graviton — cheaper)
- **Memory:** 128MB (sufficient for DynamoDB reads/writes)
- **Timeout:** 10 seconds
- **Packaging:** Zip files created from the `lambdas/` directories

### IAM Permissions

**get-subscription Lambda:**
- DynamoDB: `GetItem` on `maestro-subscriptions`

**handle-webhook Lambda:**
- DynamoDB: `PutItem` on `maestro-subscriptions`
- DynamoDB: `UpdateItem` on `maestro-subscriptions`

### Environment Variables

**get-subscription:**
- `TABLE_NAME` — DynamoDB table name

**handle-webhook:**
- `TABLE_NAME` — DynamoDB table name
- `WEBHOOK_SECRET` — Lemon Squeezy webhook signing secret (passed as Terraform variable, stored in Lambda env)

---

## Bootstrap (Terraform State)

A separate `bootstrap/` config creates:
- **S3 bucket:** `maestro-terraform-state-{account_id}` with versioning enabled, encryption at rest
- **DynamoDB table:** `maestro-terraform-locks` for state locking

Run once with `terraform init && terraform apply` from `bootstrap/`, then the main `terraform/` config references it as backend.

---

## Outputs

The main Terraform config outputs these values (needed by the Maestro app):

| Output | Description |
|--------|-------------|
| `cognito_user_pool_id` | Cognito User Pool ID |
| `cognito_app_client_id` | Cognito App Client ID |
| `api_gateway_url` | Base URL for the HTTP API |

---

## What's NOT in Scope

- Custom domain for API Gateway — use default URL for now
- Email customization for Cognito verification emails — use defaults
- Rate limiting — API Gateway has built-in throttling defaults (10k req/s)
- Monitoring/alerting — can add CloudWatch alarms later
- Multi-environment (staging/prod) — single environment for launch
