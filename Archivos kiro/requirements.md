# Requirements

## Performance

Online single PIN/XPM requests must respond with p95 latency less than or equal to 1 second.

The measurement starts when the request reaches API Gateway and ends when the response is returned.

The SLA includes:

- API Gateway
- Microservice processing
- Authorization
- PIN resolution
- Database reads
- Extension tables
- Merge logic
- Filtering
- Selection
- Serialization

The SLA also applies when extension tables are involved.

## Selective XPM Access

Consumers must be able to request specific XPM sections and fields.

The system must avoid unnecessary processing of sections and fields that are not needed or not authorized.

Current projection through `dataRequested` exists but is applied after the full XPM is read and deserialized.

## Query Keys

The business requires support for new query keys beyond document type and document number.

Required and expected keys include:

- `accountNumber`
- `firstLastName`
- `contactType`
- `contactAsReported`
- Future query keys

## Consumer Products

The consumer product landscape is broad and expected to grow across Experian Colombia.

The required sections and fields per product are not currently defined for all products and must be defined as part of the project.

## Granular Access Control

The system must support access control at XPM section and field level.

If a consumer requests an unauthorized field, the field must be omitted from the response and the omission must be logged.

Granular authorization must be auditable per request.

Data Governance functionally administers permissions by section and field.

The technical ownership and implementation model for granular authorization are not currently defined.

## PII and PCI Handling

The system must securely handle PII and PCI data.

Known classified fields include:

| Field | Classification |
|---|---|
| `accountNumber` | PCI |
| `fullName` | PII |
| `firstLastName` | PII |
| `firstName` | PII |
| `secondName` | PII |
| `personIdNumber` | PII |

The list of PII and PCI fields may be more extensive.

There must not be a combination of more than two fields classified as PII in the same audit log entry. This restriction applies to audit logs only; consumer requests and responses are not restricted by this rule when the consumer is authorized.

PII, PHI, and PCI data must not be logged in clear text.

## Generation Management

The system must support access to the active generation and the immediately previous generation.

The default generation retention must be 2 generations.

The retained generation count must be configurable.

All consumers read from the active generation.

A generation must not become active until loading and validation checks have completed.

Generation cleanup must delete associated HBase and S3 artifacts.

## Realtime Data

The target architecture must support realtime writes for realtime data stores.

Current online reads may use realtime state, pinned realtime events, and VLE-specific state depending on request context and configuration.

## Availability

The solution must provide high availability within a single AWS region.

Minimum requirement:

- 2 Availability Zones

Preferred requirement:

- 3 Availability Zones

## Disaster Recovery

The current solution has no disaster recovery architecture.

The solution must define disaster recovery in a different region and account.

DR scope includes:

- API Gateway
- Data Provisioning Service or derived microservices
- Database

DR targets:

| Metric | Target |
|---|---:|
| RTO | 4 hours |
| RPO | 24 hours |

DR must be tested every 6 months.

## Backups

Backups must be immutable and must protect against ransomware scenarios.

Minimum backup frequency is once per day.

Restore from backups must have an expected RTO less than or equal to 3 hours.

## Security

The solution must:

- Restrict direct database access by roles.
- Encrypt data in transit.
- Encrypt data at rest.
- Apply least privilege to IAM roles and policies.
- Avoid logging PII, PHI, or PCI in clear text.
- Provide auditable access decisions for granular authorization.

## Compliance

The database must comply with PCI certification standards.

## Observability and Audit

The solution must expose metrics and logs that allow analysis of:

- End-to-end latency.
- Latency by processing phase.
- PIN resolution time.
- State read time.
- Dehydrate time.
- Extension table latency and failures.
- View generation time.
- XPM selection time.
- Serialization time.
- Kerberos refresh events.
- Authorization decisions per request.

Preferred or target observability and audit tools include:

- CloudWatch
- CloudTrail
- AWS Config
- Dynatrace
- Datadog

## Non-Production Data Anonymization

The system must allow periodic extraction of a production sample, anonymization, and loading into an equivalent non-production database.

This capability is not part of the core online query path but must be considered.
