import * as cdk from 'aws-cdk-lib';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as secretsmanager from 'aws-cdk-lib/aws-secretsmanager';
import { Construct } from 'constructs';

export interface BackupStackProps extends cdk.StackProps {
  /**
   * The name prefix for the backup bucket
   * @default 'homelab-backup'
   */
  bucketNamePrefix?: string;

  /**
   * Number of days to transition objects to Glacier
   * @default 90
   */
  transitionToGlacierDays?: number;

  /**
   * Number of days to expire old versions
   * @default 365
   */
  expireOldVersionsDays?: number;

  /**
   * Enable versioning for the bucket
   * @default true
   */
  enableVersioning?: boolean;

  /**
   * Enable encryption at rest
   * @default true
   */
  enableEncryption?: boolean;

  /**
   * Create IAM user for backup access
   * @default true
   */
  createBackupUser?: boolean;

  /**
   * Store access keys in AWS Secrets Manager
   * @default false
   */
  storeKeysInSecretsManager?: boolean;
}

export class BackupStack extends cdk.Stack {
  public readonly backupBucket: s3.Bucket;
  public readonly backupUser?: iam.User;
  public readonly backupUserAccessKey?: iam.CfnAccessKey;
  public readonly backupCredentialsSecret?: secretsmanager.Secret;

  constructor(scope: Construct, id: string, props?: BackupStackProps) {
    super(scope, id, props);

    const bucketNamePrefix = props?.bucketNamePrefix || 'homelab-backup';
    const transitionToGlacierDays = props?.transitionToGlacierDays ?? 90;
    const expireOldVersionsDays = props?.expireOldVersionsDays ?? 365;
    const enableVersioning = props?.enableVersioning ?? true;
    const enableEncryption = props?.enableEncryption ?? true;
    const createBackupUser = props?.createBackupUser ?? true;
    const storeKeysInSecretsManager = props?.storeKeysInSecretsManager ?? false;

    // Create S3 bucket for backups with best practices
    this.backupBucket = new s3.Bucket(this, 'BackupBucket', {
      bucketName: `${bucketNamePrefix}-${this.account}-${this.region}`,

      // Enable versioning to protect against accidental deletions
      versioned: enableVersioning,

      // Encryption at rest
      encryption: enableEncryption
        ? s3.BucketEncryption.S3_MANAGED
        : s3.BucketEncryption.UNENCRYPTED,

      // Block all public access
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,

      // Enforce SSL for all requests
      enforceSSL: true,

      // Prevent accidental deletion of the bucket
      removalPolicy: cdk.RemovalPolicy.RETAIN,

      // Auto-delete objects when bucket is removed (set to false for production)
      autoDeleteObjects: false,

      // Lifecycle rules for cost optimization
      lifecycleRules: [
        {
          id: 'transition-to-glacier',
          enabled: true,
          transitions: [
            {
              storageClass: s3.StorageClass.GLACIER,
              transitionAfter: cdk.Duration.days(transitionToGlacierDays),
            },
          ],
        },
        {
          id: 'expire-old-versions',
          enabled: enableVersioning,
          noncurrentVersionExpiration: cdk.Duration.days(expireOldVersionsDays),
        },
      ],

      // Enable object lock for compliance (optional)
      // objectLockEnabled: true,

      // Intelligent tiering for automatic cost optimization
      intelligentTieringConfigurations: [
        {
          name: 'archive-access',
          archiveAccessTierTime: cdk.Duration.days(90),
          deepArchiveAccessTierTime: cdk.Duration.days(180),
        },
      ],
    });

    // Add tags for better resource management
    cdk.Tags.of(this.backupBucket).add('Purpose', 'Backup');
    cdk.Tags.of(this.backupBucket).add('Environment', 'Homelab');
    cdk.Tags.of(this.backupBucket).add('ManagedBy', 'CDK');

    // Output the bucket name and ARN
    new cdk.CfnOutput(this, 'BackupBucketName', {
      value: this.backupBucket.bucketName,
      description: 'The name of the backup S3 bucket',
      exportName: `${this.stackName}-BucketName`,
    });

    new cdk.CfnOutput(this, 'BackupBucketArn', {
      value: this.backupBucket.bucketArn,
      description: 'The ARN of the backup S3 bucket',
      exportName: `${this.stackName}-BucketArn`,
    });

    // Optionally create an IAM user for backup operations
    if (createBackupUser) {
      // Create IAM user with least privilege
      this.backupUser = new iam.User(this, 'BackupUser', {
        userName: `${bucketNamePrefix}-user`,
        path: '/backup/',
      });

      // Create custom policy for read/write access to the bucket
      const backupPolicy = new iam.Policy(this, 'BackupUserPolicy', {
        policyName: `${bucketNamePrefix}-policy`,
        statements: [
          new iam.PolicyStatement({
            sid: 'ListBucket',
            effect: iam.Effect.ALLOW,
            actions: [
              's3:ListBucket',
              's3:GetBucketLocation',
              's3:ListBucketVersions',
              's3:ListBucketMultipartUploads',
            ],
            resources: [this.backupBucket.bucketArn],
          }),
          new iam.PolicyStatement({
            sid: 'ReadWriteObjects',
            effect: iam.Effect.ALLOW,
            actions: [
              's3:GetObject',
              's3:GetObjectVersion',
              's3:PutObject',
              's3:DeleteObject',
              's3:DeleteObjectVersion',
              's3:AbortMultipartUpload',
              's3:ListMultipartUploadParts',
            ],
            resources: [`${this.backupBucket.bucketArn}/*`],
          }),
        ],
      });

      // Attach policy to user
      this.backupUser.attachInlinePolicy(backupPolicy);

      // Create access key for the backup user
      this.backupUserAccessKey = new iam.CfnAccessKey(this, 'BackupUserAccessKey', {
        userName: this.backupUser.userName,
      });

      if (storeKeysInSecretsManager) {
        // Store credentials in AWS Secrets Manager
        this.backupCredentialsSecret = new secretsmanager.Secret(this, 'BackupCredentials', {
          secretName: `${bucketNamePrefix}-credentials`,
          description: 'Backup user credentials for S3 bucket access',
          secretObjectValue: {
            accessKeyId: cdk.SecretValue.unsafePlainText(this.backupUserAccessKey.ref),
            secretAccessKey: cdk.SecretValue.unsafePlainText(
              this.backupUserAccessKey.attrSecretAccessKey
            ),
            bucketName: cdk.SecretValue.unsafePlainText(this.backupBucket.bucketName),
            region: cdk.SecretValue.unsafePlainText(this.region),
          },
        });

        new cdk.CfnOutput(this, 'BackupCredentialsSecretArn', {
          value: this.backupCredentialsSecret.secretArn,
          description: 'ARN of the secret containing backup credentials',
        });
      } else {
        // Output credentials directly (for CloudFormation outputs)
        new cdk.CfnOutput(this, 'BackupUserAccessKeyId', {
          value: this.backupUserAccessKey.ref,
          description: 'Access Key ID for backup user (store securely)',
        });

        new cdk.CfnOutput(this, 'BackupUserSecretAccessKey', {
          value: this.backupUserAccessKey.attrSecretAccessKey,
          description: 'Secret Access Key for backup user (store securely)',
        });
      }

      new cdk.CfnOutput(this, 'BackupUserName', {
        value: this.backupUser.userName,
        description: 'IAM user for backup operations',
      });

      new cdk.CfnOutput(this, 'BackupUserArn', {
        value: this.backupUser.userArn,
        description: 'ARN of the IAM user for backup operations',
      });
    }
  }
}
