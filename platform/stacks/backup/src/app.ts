#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { BackupStack } from './backup-stack';

const app = new cdk.App();

// Create the backup stack
new BackupStack(app, 'HomelabBackupStack', {
  // Explicitly set the environment (replace with your AWS account and region)
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT || process.env.AWS_ACCOUNT_ID,
    region: process.env.CDK_DEFAULT_REGION || process.env.AWS_REGION || 'us-east-1',
  },

  // Stack configuration
  description: 'S3 bucket for homelab Kubernetes cluster backups',

  // Custom properties for the backup stack
  bucketNamePrefix: process.env.BACKUP_BUCKET_PREFIX || 'homelab-backup',
  transitionToGlacierDays: parseInt(process.env.GLACIER_TRANSITION_DAYS || '90', 10),
  expireOldVersionsDays: parseInt(process.env.EXPIRE_OLD_VERSIONS_DAYS || '365', 10),
  enableVersioning: process.env.ENABLE_VERSIONING !== 'false',
  enableEncryption: process.env.ENABLE_ENCRYPTION !== 'false',
  createBackupUser: process.env.CREATE_BACKUP_USER !== 'false',
  storeKeysInSecretsManager: process.env.STORE_KEYS_IN_SECRETS_MANAGER === 'true',

  // Tags for the entire stack
  tags: {
    Project: 'Homelab',
    ManagedBy: 'CDK',
    Component: 'Backup',
  },
});

app.synth();
