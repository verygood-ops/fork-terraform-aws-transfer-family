#####################################################################################
# AWS Transfer Family SFTP Connector Module
# This module creates an AWS Transfer Family SFTP connector to connect an S3 bucket to an SFTP server
#####################################################################################

######################################
# Defaults and Locals
######################################

data "aws_caller_identity" "current" {}
locals {
  should_scan = false
  logging_role = length(aws_iam_role.connector_logging_role) > 0 ? aws_iam_role.connector_logging_role[0].arn : null
  
  # Use provided secret ID or create new one
  effective_secret_id = var.user_secret_id != null ? var.user_secret_id : (local.create_secret ? aws_secretsmanager_secret.sftp_credentials[0].arn : null)
  
  # URL formatting
  sftp_url = startswith(var.url, "sftp://") ? var.url : "sftp://${var.url}"

  create_secret = var.user_secret_id == null
}

#####################################################################################
# Validation Checks
#####################################################################################

check "credentials_provided" {
  assert {
    condition     = var.user_secret_id != null || length(var.trusted_host_keys) > 0 || (var.sftp_username != "" && var.sftp_private_key != "")
    error_message = "You must provide either: 1) existing_secret_arn, 2) trusted_host_keys, or 3) sftp_username and sftp_private_key to create a new secret."
  }
}

resource "terraform_data" "trusted_host_keys_warning" {
  count = length(var.trusted_host_keys) == 0 ? 1 : 0
  
  provisioner "local-exec" {
    command = "echo 'WARNING: No trusted host keys provided. The connector will deploy but may require manual host key configuration for secure connections.'"
  }
}

#####################################################################################
# Secrets Manager Secret (only when create_secret is true)
#####################################################################################

resource "aws_secretsmanager_secret" "sftp_credentials" {
  count       = local.create_secret ? 1 : 0
  name        = var.secret_name
  description = "SFTP credentials for connector"
  kms_key_id  = var.secrets_manager_kms_key_arn
}

resource "aws_secretsmanager_secret_rotation" "sftp_credentials_rotation" {
  count           = local.create_secret ? 1 : 0
  secret_id       = aws_secretsmanager_secret.sftp_credentials[0].id
  rotation_lambda_arn = aws_lambda_function.rotation_lambda[0].arn

  rotation_rules {
    automatically_after_days = 30
  }
}

resource "aws_lambda_function" "rotation_lambda" {
  count         = local.create_secret ? 1 : 0
  filename      = data.archive_file.rotation_lambda_zip[0].output_path
  function_name = "secretsmanager-rotation-${var.secret_name}"
  role          = aws_iam_role.rotation_lambda_role[0].arn
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.9"
  timeout       = 30
}

resource "aws_iam_role" "rotation_lambda_role" {
  count = local.create_secret ? 1 : 0
  name  = "secretsmanager-rotation-role-${var.secret_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "rotation_lambda_basic" {
  count      = local.create_secret ? 1 : 0
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.rotation_lambda_role[0].name
}

resource "aws_lambda_permission" "allow_secretsmanager" {
  count         = local.create_secret ? 1 : 0
  statement_id  = "AllowExecutionFromSecretsManager"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.rotation_lambda[0].function_name
  principal     = "secretsmanager.amazonaws.com"
}

data "archive_file" "rotation_lambda_zip" {
  count       = local.create_secret ? 1 : 0
  type        = "zip"
  output_path = "/tmp/rotation_lambda.zip"
  source {
    content = "def lambda_handler(event, context): pass"
    filename = "lambda_function.py"
  }
}

resource "aws_secretsmanager_secret_version" "sftp_credentials" {
  count     = local.create_secret ? 1 : 0
  secret_id = aws_secretsmanager_secret.sftp_credentials[0].id
  secret_string = jsonencode({
    Username   = var.sftp_username
    PrivateKey = var.sftp_private_key
  })
}

#####################################################################################
# Data Sources
#####################################################################################

data "aws_region" "current" {}

# Try to get connector IP information via AWS CLI
data "external" "connector_ips" {
  program = ["bash", "-c", <<-EOF
    # Check if AWS CLI is available
    if ! command -v aws >/dev/null 2>&1; then
      echo "{\"ips\": \"\", \"status\": \"cli_not_available\", \"note\": \"AWS CLI not found\"}"
      exit 0
    fi
    
    # Try to describe the connector and extract any IP information
    connector_info=$(aws transfer describe-connector --connector-id "${aws_transfer_connector.sftp_connector.id}" --region "${data.aws_region.current.id}" 2>/dev/null || echo "{}")
    
    # Extract IP addresses if they exist and format as comma-separated string
    ips=$(echo "$connector_info" | jq -r '.Connector.ServiceManagedEgressIpAddresses // [] | join(",")')
    
    if [ -n "$ips" ] && [ "$ips" != "" ]; then
      echo "{\"ips\": \"$ips\", \"status\": \"found\"}"
    else
      echo "{\"ips\": \"\", \"status\": \"not_available\", \"note\": \"No IP addresses available via API\"}"
    fi
  EOF
  ]
  
  depends_on = [aws_transfer_connector.sftp_connector]
}



# IAM role for Lambda
resource "aws_iam_role" "lambda_role" {
  count = local.should_scan ? 1 : 0
  
  name = "transfer-connector-lambda-role-${var.connector_name}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

# IAM policy for Lambda
resource "aws_iam_role_policy" "lambda_policy" {
  count = local.should_scan ? 1 : 0
  
  name = "transfer-connector-lambda-policy-${var.connector_name}"
  role = aws_iam_role.lambda_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "transfer:DescribeConnector"
        ]
        Resource = "*"
      }
    ]
  })
}

#####################################################################################
# SFTP Connector
#####################################################################################

resource "aws_transfer_connector" "sftp_connector" {
  depends_on = [
    aws_iam_role_policy_attachment.connector_logging_policy
  ]
  
  access_role = var.access_role
  url         = local.sftp_url

  # SFTP config - always include secret, optionally include trusted host keys
  sftp_config {
    user_secret_id    = local.effective_secret_id
    trusted_host_keys = length(var.trusted_host_keys) > 0 ? var.trusted_host_keys : null
  }

  logging_role = local.logging_role
  security_policy_name = var.security_policy_name

  tags = merge(
    var.tags,
    {
      Name = var.connector_name
    }
  )

}

resource "terraform_data" "discover_and_test_connector" {
  count      = var.test_connector_post_deployment ? 1 : 0
  depends_on = [aws_transfer_connector.sftp_connector]
  
  provisioner "local-exec" {
    command = <<-EOT
      # Wait 10 seconds for connector to be fully ready
      echo "Waiting 10 seconds for connector to be fully ready..."
      sleep 10
      
      # Check if AWS CLI is available
      if ! command -v aws &> /dev/null; then
        echo "AWS CLI not found - connector testing skipped"
        echo "Deployment completed successfully"
        exit 0
      fi
      
      # Check AWS CLI version (requires 2.28.x or above)
      AWS_VERSION=$(aws --version 2>&1 | cut -d'/' -f2 | cut -d' ' -f1)
      if [ -n "$AWS_VERSION" ]; then
        MAJOR=$(echo "$AWS_VERSION" | cut -d'.' -f1)
        MINOR=$(echo "$AWS_VERSION" | cut -d'.' -f2)
        
        if [ "$MAJOR" -lt 2 ] || ([ "$MAJOR" -eq 2 ] && [ "$MINOR" -lt 28 ]); then
          echo "AWS CLI version $AWS_VERSION detected - connector testing requires version 2.28.x or above"
          echo "connector testing skipped"
          echo "Deployment completed successfully"
          exit 0
        fi
        echo "AWS CLI version $AWS_VERSION - version check passed"
      else
        echo "Could not determine AWS CLI version - connector testing skipped"
        echo "Deployment completed successfully"
        exit 0
      fi
      
      # Check if jq is available (required for JSON parsing)
      if ! command -v jq &> /dev/null; then
        echo "jq not found - connector testing skipped"
        echo "Deployment completed successfully"
        exit 0
      fi
      
      echo "Testing connection to discover host key..."
      
      MAX_RETRIES=3
      RETRY_COUNT=0
      HOST_KEY=""
      
      while [ $RETRY_COUNT -lt $MAX_RETRIES ] && [ -z "$HOST_KEY" ]; do
        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo "Attempt $RETRY_COUNT/$MAX_RETRIES: Testing connection..."
        
        DISCOVERY_RESULT=$(aws transfer test-connection \
          --connector-id ${aws_transfer_connector.sftp_connector.id} \
          --region ${data.aws_region.current.id} \
          --output json 2>/dev/null || echo '{}')
        
        echo "DEBUG - Discovery Result: $DISCOVERY_RESULT"
        
        STATUS=$(echo "$DISCOVERY_RESULT" | jq -r '.Status // empty')
        echo "DEBUG - Status: $STATUS"
        
        if [ "$STATUS" = "ERROR" ]; then
          ERROR_MSG=$(echo "$DISCOVERY_RESULT" | jq -r '.StatusMessage // empty')
          echo "Connection test failed: $ERROR_MSG"
          echo "DEBUG - Full error response: $DISCOVERY_RESULT"
          
          if echo "$ERROR_MSG" | grep -q "Cannot access secret manager"; then
            echo "Secret manager not ready, waiting 10 seconds..."
            sleep 10
            continue
          fi
        elif [ "$STATUS" = "OK" ]; then
          echo "Connection test successful - connector is properly configured"
          echo "Deployment completed successfully"
          exit 0
        fi
        
        HOST_KEY=$(echo "$DISCOVERY_RESULT" | jq -r '.SftpConnectionDetails.HostKey // empty')
        echo "DEBUG - Host Key: $HOST_KEY"
        
        if [ -n "$HOST_KEY" ] && [ "$HOST_KEY" != "null" ]; then
          echo "Host key discovered: $HOST_KEY"
          break
        else
          echo "Host key not found, retrying in 10s..."
          sleep 10
        fi
      done
      
      if [ -n "$HOST_KEY" ] && [ "$HOST_KEY" != "null" ]; then
        echo "Updating connector with discovered host key..."
        UPDATE_RESULT=$(aws transfer update-connector \
          --connector-id ${aws_transfer_connector.sftp_connector.id} \
          --region ${data.aws_region.current.id} \
          --url "${local.sftp_url}" \
          --access-role "${var.access_role}" \
          --logging-role "${local.logging_role}" \
          --sftp-config "UserSecretId=${local.effective_secret_id},TrustedHostKeys=$HOST_KEY" \
          --output json)
        
        echo "DEBUG - Update Result: $UPDATE_RESULT"
        
        echo "Testing final connection with trusted host key..."
        FINAL_TEST=$(aws transfer test-connection \
          --connector-id ${aws_transfer_connector.sftp_connector.id} \
          --region ${data.aws_region.current.id} \
          --output json)
        
        echo "DEBUG - Final Test Result: $FINAL_TEST"
        
        FINAL_STATUS=$(echo "$FINAL_TEST" | jq -r '.Status')
        echo "Final connection status: $FINAL_STATUS"
        
        if [ "$FINAL_STATUS" = "OK" ]; then
          echo "Connector configured and tested successfully"
        else
          echo "Final test failed: $(echo "$FINAL_TEST" | jq -r '.StatusMessage')"
        fi
      else
        echo "Failed to discover host key after $MAX_RETRIES attempts"
        echo "Deployment completed with warnings - connector may need manual configuration"
        exit 0
      fi
    EOT
  }
}

#####################################################################################
# CloudWatch Logging Role and Policy (if not provided)
#####################################################################################

resource "aws_iam_role" "connector_logging_role" {
  count = var.logging_role == null ? 1 : 0
  
  name = "transfer-connector-logging-role-${var.connector_name}"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "transfer.amazonaws.com"
        }
      }
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "connector_logging_policy" {
  count      = var.logging_role == null ? 1 : 0
  role       = aws_iam_role.connector_logging_role[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSTransferLoggingAccess"
}

#####################################################################################
# Optional IAM Policy Management for Access Role
#####################################################################################

# Policy for secrets manager access (when using existing secret)
resource "aws_iam_role_policy" "access_role_secrets_policy" {
  count = local.create_secret ? 1 : 0
  
  name = "transfer-connector-secrets-policy-${var.connector_name}"
  role = var.access_role

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid = "GetConnectorSecretValue"
        Effect = "Allow"
        Action = [
          "secretsmanager:GetSecretValue"
        ]
        Resource = var.user_secret_id
      }
    ]
  })
}
