# Deployment Guide

## Option A — Heroku (MVP / Development)

```bash
heroku create motionmind-backend
heroku addons:create heroku-postgresql:standard-0
heroku addons:create heroku-redis:hobby-dev

# Set env vars
heroku config:set JWT_SECRET=$(openssl rand -hex 32)
heroku config:set NODE_ENV=production
heroku config:set CORS_ORIGIN=https://dashboard.motionmind.app
heroku config:set AWS_S3_BUCKET=motionmind-reports
# ... (see .env.example for full list)

git push heroku main
heroku run psql $DATABASE_URL -f migrations/001_init.sql
heroku logs --tail
```

## Option B — AWS (Production / HIPAA)

### Architecture
```
Internet → ALB (HTTPS) → EC2 Auto Scaling Group → Node.js
                                    ↓
                              RDS PostgreSQL (private subnet)
                                    ↓
                              ElastiCache Redis (private subnet)
                                    ↓
                              S3 (reports, encrypted)
```

### Steps

```bash
# 1. Create VPC with private subnets
aws ec2 create-vpc --cidr-block 10.0.0.0/16

# 2. RDS PostgreSQL (Multi-AZ for HA)
aws rds create-db-instance \
  --db-instance-identifier motionmind-prod \
  --db-instance-class db.t3.small \
  --engine postgres \
  --engine-version 15.4 \
  --allocated-storage 100 \
  --storage-encrypted \
  --multi-az \
  --backup-retention-period 7

# 3. ElastiCache Redis
aws elasticache create-replication-group \
  --replication-group-id motionmind-redis \
  --engine redis \
  --cache-node-type cache.t3.micro

# 4. S3 Bucket (private, encrypted)
aws s3 mb s3://motionmind-reports
aws s3api put-bucket-encryption --bucket motionmind-reports \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
aws s3api put-public-access-block --bucket motionmind-reports \
  --public-access-block-configuration "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# 5. Elastic Beanstalk
eb init motionmind-backend --platform node.js --region us-east-1
eb create production --scale 2
eb setenv $(cat .env | tr '\n' ' ')
eb deploy

# 6. Run DB migration
eb ssh -- "psql $DATABASE_URL -f migrations/001_init.sql"
```

## Option C — Docker Compose (Local Development)

```yaml
# docker-compose.yml
version: "3.9"
services:
  api:
    build: .
    ports: ["3000:3000"]
    env_file: .env
    depends_on: [db, redis]

  db:
    image: postgres:15-alpine
    environment:
      POSTGRES_DB: motionmind
      POSTGRES_USER: user
      POSTGRES_PASSWORD: password
    volumes: ["pgdata:/var/lib/postgresql/data"]

  redis:
    image: redis:7-alpine

volumes:
  pgdata:
```

```bash
docker compose up -d
docker compose exec api psql $DATABASE_URL -f migrations/001_init.sql
docker compose exec api npm run db:seed
```

## Health Check

```bash
curl https://api.motionmind.app/health
# → {"status":"ok","db":"ok","timestamp":"...","version":"1.0.0"}
```
