# Homelab Backup Stack

AWS CDK stack for provisioning an S3 bucket to be used for Kubernetes cluster backups.

## Features

- **S3 Bucket** with backup best practices:
  - Versioning enabled for data protection
  - Server-side encryption (SSE-S3)
  - Block all public access
  - SSL/TLS enforcement
  - Lifecycle policies for cost optimization
  - Intelligent tiering for automatic cost savings

- **IAM User** with read/write access to the bucket
- **Access Keys** for programmatic access
- **Cost Optimization**:
  - Automatic transition to Glacier after 90 days
  - Old version expiration after 365 days
  - Intelligent tiering for frequently accessed objects

## Prerequisites

- Node.js 18+ and npm
- AWS CLI configured with appropriate credentials
- AWS CDK CLI: `npm install -g aws-cdk`

## Setup

1. Install dependencies:
```bash
npm install
```

2. Configure AWS credentials:
```bash
aws configure
```

3. Bootstrap CDK (first time only):
```bash
cdk bootstrap aws://ACCOUNT-ID/REGION
```

## Usage

### Synthesize CloudFormation template

```bash
npm run synth
```

### Preview changes

```bash
npm run diff
```

### Deploy the stack

```bash
npm run deploy
```

### Destroy the stack

```bash
npm run destroy
```

## Configuration

You can customize the stack behavior using environment variables:

```bash
# Bucket name prefix (default: homelab-backup)
export BACKUP_BUCKET_PREFIX="my-backup"

# Days before transitioning to Glacier (default: 90)
export GLACIER_TRANSITION_DAYS="60"

# Days before expiring old versions (default: 365)
export EXPIRE_OLD_VERSIONS_DAYS="180"

# Enable/disable versioning (default: true)
export ENABLE_VERSIONING="true"

# Enable/disable encryption (default: true)
export ENABLE_ENCRYPTION="true"

# Create IAM user for backup access (default: true)
export CREATE_BACKUP_USER="true"

# Store credentials in AWS Secrets Manager (default: false)
export STORE_KEYS_IN_SECRETS_MANAGER="false"

# AWS Account and Region
export AWS_ACCOUNT_ID="123456789012"
export AWS_REGION="us-east-1"

npm run deploy
```

## Outputs

After deployment, the stack will output:

- **BackupBucketName**: The name of the S3 bucket
- **BackupBucketArn**: The ARN of the S3 bucket

If `CREATE_BACKUP_USER=true` (default):
- **BackupUserName**: IAM user for backup operations
- **BackupUserArn**: ARN of the IAM user

If `STORE_KEYS_IN_SECRETS_MANAGER=false` (default):
- **BackupUserAccessKeyId**: Access key ID (store securely)
- **BackupUserSecretAccessKey**: Secret access key (store securely)

If `STORE_KEYS_IN_SECRETS_MANAGER=true`:
- **BackupCredentialsSecretArn**: ARN of the secret in AWS Secrets Manager containing all credentials

## IAM User for Backup Access

The stack creates a dedicated IAM user with read/write permissions to the S3 bucket. This user has a custom policy with least-privilege access:

**Permissions granted:**
- `s3:ListBucket` - List objects in the bucket
- `s3:GetBucketLocation` - Get bucket location
- `s3:ListBucketVersions` - List object versions (for versioned backups)
- `s3:ListBucketMultipartUploads` - List multipart uploads in progress
- `s3:GetObject` - Download objects
- `s3:GetObjectVersion` - Download specific object versions
- `s3:PutObject` - Upload objects
- `s3:DeleteObject` - Delete objects
- `s3:DeleteObjectVersion` - Delete specific object versions
- `s3:AbortMultipartUpload` - Cancel incomplete multipart uploads
- `s3:ListMultipartUploadParts` - List parts of a multipart upload

**Security features:**
- User is placed in `/backup/` path for better organization
- Inline policy is scoped only to the specific backup bucket
- No additional permissions beyond S3 bucket access
- Access keys can be stored in AWS Secrets Manager for enhanced security

### Option 1: CloudFormation Outputs (Default)

By default, access keys are exposed via CloudFormation outputs. You can retrieve them after deployment:

```bash
aws cloudformation describe-stacks \
  --stack-name HomelabBackupStack \
  --query 'Stacks[0].Outputs'
```

### Option 2: AWS Secrets Manager (Recommended)

Set `STORE_KEYS_IN_SECRETS_MANAGER=true` to store credentials in AWS Secrets Manager:

```bash
export STORE_KEYS_IN_SECRETS_MANAGER=true
npm run deploy
```

Then retrieve credentials programmatically:

```bash
aws secretsmanager get-secret-value \
  --secret-id homelab-backup-credentials \
  --query SecretString \
  --output text | jq .
```

## Integration with Kubernetes

To use this bucket with your Kubernetes backups (e.g., Velero):

### Method 1: Using External Secrets Operator with AWS Secrets Manager

1. First, deploy the stack with Secrets Manager enabled:
```bash
export STORE_KEYS_IN_SECRETS_MANAGER=true
npm run deploy
```

2. Create SecretStore for AWS Secrets Manager:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-backend
  namespace: velero
spec:
  provider:
    aws:
      service: SecretsManager
      region: us-east-1
      auth:
        # Use IRSA or IAM role for authentication
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
```

3. Create External Secret to sync backup credentials:

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: backup-credentials
  namespace: velero
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-backend
    kind: SecretStore
  target:
    name: cloud-credentials
    creationPolicy: Owner
    template:
      data:
        cloud: |
          [default]
          aws_access_key_id={{ .accessKeyId }}
          aws_secret_access_key={{ .secretAccessKey }}
  dataFrom:
    - extract:
        key: homelab-backup-credentials
```

4. Configure Velero to use the S3 bucket:

```bash
velero install \
  --provider aws \
  --bucket <BackupBucketName> \
  --use-node-agent \
  --secret-file ./cloud-credentials \
  --backup-location-config region=us-east-1 \
  --snapshot-location-config region=us-east-1
```

### Method 2: Using CloudFormation Outputs Directly

1. Get the credentials from CloudFormation outputs:

```bash
export AWS_ACCESS_KEY_ID=$(aws cloudformation describe-stacks \
  --stack-name HomelabBackupStack \
  --query 'Stacks[0].Outputs[?OutputKey==`BackupUserAccessKeyId`].OutputValue' \
  --output text)

export AWS_SECRET_ACCESS_KEY=$(aws cloudformation describe-stacks \
  --stack-name HomelabBackupStack \
  --query 'Stacks[0].Outputs[?OutputKey==`BackupUserSecretAccessKey`].OutputValue' \
  --output text)
```

2. Create credentials file for Velero:

```bash
cat > credentials-velero <<EOF
[default]
aws_access_key_id=${AWS_ACCESS_KEY_ID}
aws_secret_access_key=${AWS_SECRET_ACCESS_KEY}
EOF
```

3. Create Kubernetes secret manually:

```bash
kubectl create secret generic cloud-credentials \
  --namespace velero \
  --from-file=cloud=credentials-velero
```

4. Clean up the credentials file:

```bash
rm credentials-velero
```

## Security Considerations

- The bucket has all public access blocked
- SSL/TLS is enforced for all requests
- Versioning protects against accidental deletions
- The bucket has `RETAIN` removal policy to prevent data loss
- Access keys should be stored in a secrets manager (AWS Secrets Manager, External Secrets Operator)
- Consider enabling MFA delete for additional protection
- Review and adjust lifecycle policies based on your retention requirements

## Cost Optimization

The stack includes several cost optimization features:

1. **Lifecycle transitions**: Objects automatically move to Glacier after 90 days
2. **Intelligent tiering**: Automatically moves objects between access tiers
3. **Old version expiration**: Removes old versions after 365 days
4. **Archive access tiers**: Deep archive for long-term storage

Adjust these settings based on your backup retention policy and budget.

## Troubleshooting

### Access Denied Errors

If you encounter access denied errors, ensure:
- Your AWS credentials have sufficient permissions
- The IAM user has the correct policies attached
- The bucket policy allows the required operations

### CDK Bootstrap Issues

If deployment fails with bootstrap errors:
```bash
cdk bootstrap aws://ACCOUNT-ID/REGION --force
```

### Stack Already Exists

If the stack already exists and you want to update it:
```bash
npm run diff  # Review changes
npm run deploy  # Apply updates
```

## License

MIT
