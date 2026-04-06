# Maestro Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy AWS infrastructure for Maestro's account-based subscription system — Cognito user pool, DynamoDB subscriptions table, API Gateway with two Lambda-backed routes.

**Architecture:** Terraform manages all resources in us-east-1. A bootstrap config creates the S3 state bucket. The main config deploys Cognito, DynamoDB, API Gateway (HTTP API), and two Python Lambdas. The get-subscription Lambda reads subscription status by userId. The handle-webhook Lambda receives Lemon Squeezy events and upserts subscription records.

**Tech Stack:** Terraform, AWS (Cognito, DynamoDB, API Gateway, Lambda), Python 3.12

---

### Task 1: Scaffold the Repository

**Files:**
- Create: `/Users/pedrohm/workspace/projects/maestro-infra/.gitignore`

- [ ] **Step 1: Create the project directory and initialize git**

```bash
mkdir -p /Users/pedrohm/workspace/projects/maestro-infra
cd /Users/pedrohm/workspace/projects/maestro-infra
git init
```

- [ ] **Step 2: Create .gitignore**

Create `/Users/pedrohm/workspace/projects/maestro-infra/.gitignore`:

```
.terraform/
*.tfstate
*.tfstate.backup
*.tfvars
!terraform.tfvars.example
.terraform.lock.hcl
*.zip
__pycache__/
.DS_Store
```

- [ ] **Step 3: Create directory structure**

```bash
cd /Users/pedrohm/workspace/projects/maestro-infra
mkdir -p bootstrap terraform lambdas/get_subscription lambdas/handle_webhook
```

- [ ] **Step 4: Commit**

```bash
cd /Users/pedrohm/workspace/projects/maestro-infra
git add -A
git commit -m "chore: scaffold maestro-infra repo"
```

---

### Task 2: Bootstrap — Terraform State Backend

**Files:**
- Create: `/Users/pedrohm/workspace/projects/maestro-infra/bootstrap/main.tf`

- [ ] **Step 1: Create bootstrap/main.tf**

```hcl
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "terraform_state" {
  bucket = "maestro-terraform-state-${data.aws_caller_identity.current.account_id}"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_locks" {
  name         = "maestro-terraform-locks"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

output "state_bucket_name" {
  value = aws_s3_bucket.terraform_state.id
}

output "lock_table_name" {
  value = aws_dynamodb_table.terraform_locks.name
}
```

- [ ] **Step 2: Initialize and apply bootstrap**

```bash
cd /Users/pedrohm/workspace/projects/maestro-infra/bootstrap
terraform init
terraform apply
```

Expected: Creates S3 bucket `maestro-terraform-state-{account_id}` and DynamoDB table `maestro-terraform-locks`. Note the bucket name from the output — you'll need it in the next task.

- [ ] **Step 3: Commit**

```bash
cd /Users/pedrohm/workspace/projects/maestro-infra
git add bootstrap/
git commit -m "feat: add bootstrap config for Terraform state backend"
```

---

### Task 3: Main Terraform Config — Provider and Backend

**Files:**
- Create: `/Users/pedrohm/workspace/projects/maestro-infra/terraform/main.tf`
- Create: `/Users/pedrohm/workspace/projects/maestro-infra/terraform/variables.tf`
- Create: `/Users/pedrohm/workspace/projects/maestro-infra/terraform/outputs.tf`

- [ ] **Step 1: Create terraform/variables.tf**

```hcl
variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for resource naming"
  type        = string
  default     = "maestro"
}

variable "lemonsqueezy_webhook_secret" {
  description = "Lemon Squeezy webhook signing secret"
  type        = string
  sensitive   = true
}
```

- [ ] **Step 2: Create terraform/main.tf**

Replace `BUCKET_NAME` with the actual bucket name from the bootstrap output.

```hcl
terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    bucket         = "BUCKET_NAME"
    key            = "maestro/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "maestro-terraform-locks"
    encrypt        = true
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}
```

- [ ] **Step 3: Create terraform/outputs.tf**

```hcl
output "cognito_user_pool_id" {
  description = "Cognito User Pool ID"
  value       = aws_cognito_user_pool.main.id
}

output "cognito_app_client_id" {
  description = "Cognito App Client ID"
  value       = aws_cognito_user_pool_client.macos_app.id
}

output "api_gateway_url" {
  description = "Base URL for the HTTP API"
  value       = aws_apigatewayv2_stage.default.invoke_url
}
```

- [ ] **Step 4: Commit**

```bash
cd /Users/pedrohm/workspace/projects/maestro-infra
git add terraform/main.tf terraform/variables.tf terraform/outputs.tf
git commit -m "feat: add main Terraform config with S3 backend"
```

---

### Task 4: Cognito User Pool

**Files:**
- Create: `/Users/pedrohm/workspace/projects/maestro-infra/terraform/cognito.tf`

- [ ] **Step 1: Create terraform/cognito.tf**

```hcl
resource "aws_cognito_user_pool" "main" {
  name = "${var.project_name}-users"

  # Email as username
  username_attributes      = ["email"]
  auto_verified_attributes = ["email"]

  # Password policy
  password_policy {
    minimum_length                   = 8
    require_lowercase                = true
    require_uppercase                = true
    require_numbers                  = true
    require_symbols                  = false
    temporary_password_validity_days = 7
  }

  # Email verification
  verification_message_template {
    default_email_option = "CONFIRM_WITH_CODE"
    email_subject        = "Your Maestro verification code"
    email_message        = "Your verification code is {####}"
  }

  # Schema
  schema {
    attribute_data_type = "String"
    name                = "email"
    required            = true
    mutable             = true

    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }
}

resource "aws_cognito_user_pool_client" "macos_app" {
  name         = "${var.project_name}-macos-app"
  user_pool_id = aws_cognito_user_pool.main.id

  # Public client (no secret) — standard for native apps
  generate_secret = false

  # Auth flows for native app
  explicit_auth_flows = [
    "ALLOW_USER_PASSWORD_AUTH",
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
  ]

  # Token expiry
  id_token_validity      = 1   # 1 hour
  access_token_validity  = 1   # 1 hour
  refresh_token_validity = 30  # 30 days

  token_validity_units {
    id_token      = "hours"
    access_token  = "hours"
    refresh_token = "days"
  }

  # No hosted UI
  supported_identity_providers = []
}
```

- [ ] **Step 2: Commit**

```bash
cd /Users/pedrohm/workspace/projects/maestro-infra
git add terraform/cognito.tf
git commit -m "feat: add Cognito user pool and app client"
```

---

### Task 5: DynamoDB Table

**Files:**
- Create: `/Users/pedrohm/workspace/projects/maestro-infra/terraform/dynamodb.tf`

- [ ] **Step 1: Create terraform/dynamodb.tf**

```hcl
resource "aws_dynamodb_table" "subscriptions" {
  name         = "${var.project_name}-subscriptions"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "userId"

  attribute {
    name = "userId"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }
}
```

- [ ] **Step 2: Commit**

```bash
cd /Users/pedrohm/workspace/projects/maestro-infra
git add terraform/dynamodb.tf
git commit -m "feat: add DynamoDB subscriptions table"
```

---

### Task 6: get-subscription Lambda

**Files:**
- Create: `/Users/pedrohm/workspace/projects/maestro-infra/lambdas/get_subscription/handler.py`

- [ ] **Step 1: Create lambdas/get_subscription/handler.py**

```python
import json
import os
import boto3

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])


def handler(event, context):
    # userId comes from Cognito JWT claims, passed by API Gateway authorizer
    claims = event.get("requestContext", {}).get("authorizer", {}).get("jwt", {}).get("claims", {})
    user_id = claims.get("sub")

    if not user_id:
        return {
            "statusCode": 401,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": "Missing user ID in token"}),
        }

    response = table.get_item(Key={"userId": user_id})
    item = response.get("Item")

    if item:
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({
                "status": item.get("status", "none"),
                "currentPeriodEnd": item.get("currentPeriodEnd"),
            }),
        }

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"status": "none"}),
    }
```

- [ ] **Step 2: Commit**

```bash
cd /Users/pedrohm/workspace/projects/maestro-infra
git add lambdas/get_subscription/
git commit -m "feat: add get-subscription Lambda handler"
```

---

### Task 7: handle-webhook Lambda

**Files:**
- Create: `/Users/pedrohm/workspace/projects/maestro-infra/lambdas/handle_webhook/handler.py`

- [ ] **Step 1: Create lambdas/handle_webhook/handler.py**

```python
import hashlib
import hmac
import json
import os
from datetime import datetime, timezone

import boto3

dynamodb = boto3.resource("dynamodb")
table = dynamodb.Table(os.environ["TABLE_NAME"])
WEBHOOK_SECRET = os.environ["WEBHOOK_SECRET"]

HANDLED_EVENTS = {
    "subscription_created",
    "subscription_updated",
    "subscription_cancelled",
    "subscription_expired",
}

# Map Lemon Squeezy status to our status values
STATUS_MAP = {
    "active": "active",
    "past_due": "past_due",
    "cancelled": "cancelled",
    "expired": "expired",
    "paused": "cancelled",
    "unpaid": "past_due",
}


def verify_signature(body: str, signature: str) -> bool:
    expected = hmac.new(
        WEBHOOK_SECRET.encode("utf-8"),
        body.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()
    return hmac.compare_digest(expected, signature)


def handler(event, context):
    body = event.get("body", "")
    signature = event.get("headers", {}).get("x-signature", "")

    if not verify_signature(body, signature):
        return {
            "statusCode": 401,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": "Invalid signature"}),
        }

    payload = json.loads(body)
    event_name = payload.get("meta", {}).get("event_name", "")

    if event_name not in HANDLED_EVENTS:
        return {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"message": "Event ignored"}),
        }

    custom_data = payload.get("meta", {}).get("custom_data", {})
    user_id = custom_data.get("user_id")

    if not user_id:
        return {
            "statusCode": 400,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": "Missing user_id in custom_data"}),
        }

    attrs = payload.get("data", {}).get("attributes", {})
    ls_status = attrs.get("status", "")
    status = STATUS_MAP.get(ls_status, ls_status)
    customer_id = str(attrs.get("customer_id", ""))
    subscription_id = str(payload.get("data", {}).get("id", ""))
    current_period_end = attrs.get("renews_at") or attrs.get("ends_at") or ""
    now = datetime.now(timezone.utc).isoformat()

    table.put_item(
        Item={
            "userId": user_id,
            "status": status,
            "lemonSqueezyCustomerId": customer_id,
            "lemonSqueezySubscriptionId": subscription_id,
            "currentPeriodEnd": current_period_end,
            "updatedAt": now,
        }
    )

    return {
        "statusCode": 200,
        "headers": {"Content-Type": "application/json"},
        "body": json.dumps({"message": "OK"}),
    }
```

- [ ] **Step 2: Commit**

```bash
cd /Users/pedrohm/workspace/projects/maestro-infra
git add lambdas/handle_webhook/
git commit -m "feat: add handle-webhook Lambda handler"
```

---

### Task 8: Lambda Terraform Config (IAM + Functions)

**Files:**
- Create: `/Users/pedrohm/workspace/projects/maestro-infra/terraform/lambdas.tf`

- [ ] **Step 1: Create terraform/lambdas.tf**

```hcl
# --- Lambda packaging ---

data "archive_file" "get_subscription" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/get_subscription"
  output_path = "${path.module}/../lambdas/get_subscription.zip"
}

data "archive_file" "handle_webhook" {
  type        = "zip"
  source_dir  = "${path.module}/../lambdas/handle_webhook"
  output_path = "${path.module}/../lambdas/handle_webhook.zip"
}

# --- IAM ---

resource "aws_iam_role" "get_subscription" {
  name = "${var.project_name}-get-subscription-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "get_subscription" {
  name = "${var.project_name}-get-subscription-policy"
  role = aws_iam_role.get_subscription.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:GetItem"]
        Resource = aws_dynamodb_table.subscriptions.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
    ]
  })
}

resource "aws_iam_role" "handle_webhook" {
  name = "${var.project_name}-handle-webhook-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy" "handle_webhook" {
  name = "${var.project_name}-handle-webhook-policy"
  role = aws_iam_role.handle_webhook.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:UpdateItem"]
        Resource = aws_dynamodb_table.subscriptions.arn
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "arn:aws:logs:*:*:*"
      },
    ]
  })
}

# --- Lambda functions ---

resource "aws_lambda_function" "get_subscription" {
  function_name    = "${var.project_name}-get-subscription"
  role             = aws_iam_role.get_subscription.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  architectures    = ["arm64"]
  memory_size      = 128
  timeout          = 10
  filename         = data.archive_file.get_subscription.output_path
  source_code_hash = data.archive_file.get_subscription.output_base64sha256

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.subscriptions.name
    }
  }
}

resource "aws_lambda_function" "handle_webhook" {
  function_name    = "${var.project_name}-handle-webhook"
  role             = aws_iam_role.handle_webhook.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  architectures    = ["arm64"]
  memory_size      = 128
  timeout          = 10
  filename         = data.archive_file.handle_webhook.output_path
  source_code_hash = data.archive_file.handle_webhook.output_base64sha256

  environment {
    variables = {
      TABLE_NAME     = aws_dynamodb_table.subscriptions.name
      WEBHOOK_SECRET = var.lemonsqueezy_webhook_secret
    }
  }
}
```

- [ ] **Step 2: Commit**

```bash
cd /Users/pedrohm/workspace/projects/maestro-infra
git add terraform/lambdas.tf
git commit -m "feat: add Lambda functions and IAM roles"
```

---

### Task 9: API Gateway

**Files:**
- Create: `/Users/pedrohm/workspace/projects/maestro-infra/terraform/api_gateway.tf`

- [ ] **Step 1: Create terraform/api_gateway.tf**

```hcl
# --- HTTP API ---

resource "aws_apigatewayv2_api" "main" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["*"]
    allow_methods = ["GET", "POST", "OPTIONS"]
    allow_headers = ["Authorization", "Content-Type"]
    max_age       = 3600
  }
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.main.id
  name        = "$default"
  auto_deploy = true
}

# --- Cognito JWT Authorizer ---

resource "aws_apigatewayv2_authorizer" "cognito" {
  api_id           = aws_apigatewayv2_api.main.id
  name             = "${var.project_name}-cognito-authorizer"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    audience = [aws_cognito_user_pool_client.macos_app.id]
    issuer   = "https://cognito-idp.${var.region}.amazonaws.com/${aws_cognito_user_pool.main.id}"
  }
}

# --- GET /subscription (authenticated) ---

resource "aws_apigatewayv2_integration" "get_subscription" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.get_subscription.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_subscription" {
  api_id             = aws_apigatewayv2_api.main.id
  route_key          = "GET /subscription"
  target             = "integrations/${aws_apigatewayv2_integration.get_subscription.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.cognito.id
}

resource "aws_lambda_permission" "get_subscription" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.get_subscription.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}

# --- POST /webhook/lemonsqueezy (public) ---

resource "aws_apigatewayv2_integration" "handle_webhook" {
  api_id                 = aws_apigatewayv2_api.main.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.handle_webhook.invoke_arn
  integration_method     = "POST"
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "handle_webhook" {
  api_id    = aws_apigatewayv2_api.main.id
  route_key = "POST /webhook/lemonsqueezy"
  target    = "integrations/${aws_apigatewayv2_integration.handle_webhook.id}"
}

resource "aws_lambda_permission" "handle_webhook" {
  statement_id  = "AllowAPIGateway"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.handle_webhook.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.main.execution_arn}/*/*"
}
```

- [ ] **Step 2: Commit**

```bash
cd /Users/pedrohm/workspace/projects/maestro-infra
git add terraform/api_gateway.tf
git commit -m "feat: add API Gateway with JWT authorizer and routes"
```

---

### Task 10: Deploy and Verify

**Files:**
- Create: `/Users/pedrohm/workspace/projects/maestro-infra/terraform/terraform.tfvars.example`

- [ ] **Step 1: Create terraform.tfvars.example**

```hcl
# Copy this to terraform.tfvars and fill in your values
lemonsqueezy_webhook_secret = "your-webhook-signing-secret"
```

- [ ] **Step 2: Create terraform.tfvars with your actual secret**

```bash
cd /Users/pedrohm/workspace/projects/maestro-infra/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and set your Lemon Squeezy webhook secret
# (This file is in .gitignore — never committed)
```

- [ ] **Step 3: Initialize and apply**

```bash
cd /Users/pedrohm/workspace/projects/maestro-infra/terraform
terraform init
terraform plan
```

Review the plan — should create: 1 Cognito user pool, 1 app client, 1 DynamoDB table, 2 Lambda functions, 2 IAM roles, 2 IAM policies, 1 API Gateway, 1 stage, 1 authorizer, 2 integrations, 2 routes, 2 Lambda permissions.

```bash
terraform apply
```

Expected output includes:
- `cognito_user_pool_id` — e.g., `us-east-1_aBcDeFgHi`
- `cognito_app_client_id` — e.g., `1a2b3c4d5e6f7g8h9i0j`
- `api_gateway_url` — e.g., `https://abc123.execute-api.us-east-1.amazonaws.com`

- [ ] **Step 4: Verify Cognito — create a test user**

```bash
aws cognito-idp sign-up \
  --client-id $(terraform output -raw cognito_app_client_id) \
  --username test@example.com \
  --password TestPass123 \
  --region us-east-1

# Confirm the user (admin override since we don't have the email code)
aws cognito-idp admin-confirm-sign-up \
  --user-pool-id $(terraform output -raw cognito_user_pool_id) \
  --username test@example.com \
  --region us-east-1
```

Expected: User created and confirmed.

- [ ] **Step 5: Verify GET /subscription — authenticate and call**

```bash
# Get tokens
AUTH_RESULT=$(aws cognito-idp initiate-auth \
  --client-id $(terraform output -raw cognito_app_client_id) \
  --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters USERNAME=test@example.com,PASSWORD=TestPass123 \
  --region us-east-1)

ID_TOKEN=$(echo $AUTH_RESULT | python3 -c "import sys,json; print(json.load(sys.stdin)['AuthenticationResult']['IdToken'])")

# Call the subscription endpoint
curl -s -H "Authorization: Bearer $ID_TOKEN" \
  "$(terraform output -raw api_gateway_url)/subscription"
```

Expected: `{"status": "none"}` — user has no subscription record yet.

- [ ] **Step 6: Verify POST /webhook/lemonsqueezy — simulate a webhook**

```bash
API_URL=$(terraform output -raw api_gateway_url)

# Get the user's sub (userId) from the token
USER_ID=$(python3 -c "import json,base64; print(json.loads(base64.b64decode('$( echo $ID_TOKEN | cut -d. -f2)==='))['sub'])")

# Create a test payload
BODY='{"meta":{"event_name":"subscription_created","custom_data":{"user_id":"'$USER_ID'"}},"data":{"id":"12345","attributes":{"status":"active","customer_id":67890,"renews_at":"2026-05-05T00:00:00Z"}}}'

# Generate the signature
SECRET=$(grep lemonsqueezy_webhook_secret terraform.tfvars | cut -d'"' -f2)
SIGNATURE=$(echo -n "$BODY" | openssl dgst -sha256 -hmac "$SECRET" | awk '{print $NF}')

# Send the webhook
curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "X-Signature: $SIGNATURE" \
  -d "$BODY" \
  "$API_URL/webhook/lemonsqueezy"
```

Expected: `{"message": "OK"}`

- [ ] **Step 7: Verify the subscription was written**

```bash
curl -s -H "Authorization: Bearer $ID_TOKEN" \
  "$(terraform output -raw api_gateway_url)/subscription"
```

Expected: `{"status": "active", "currentPeriodEnd": "2026-05-05T00:00:00Z"}`

- [ ] **Step 8: Clean up test user**

```bash
aws cognito-idp admin-delete-user \
  --user-pool-id $(terraform output -raw cognito_user_pool_id) \
  --username test@example.com \
  --region us-east-1
```

- [ ] **Step 9: Commit the tfvars example**

```bash
cd /Users/pedrohm/workspace/projects/maestro-infra
git add terraform/terraform.tfvars.example
git commit -m "feat: deploy infrastructure, verify end-to-end"
```
