# RELEASE NOTES

## 3.10.0 - 8th December 2025

- Added `connection_logs` and `health_checks_logs` arguments
- Added `connection_logs_bucket_id` and `health_check_logs_bucket_id` variables
- Bumped minimum AWS provider version to `6.25.0`
- Added `target_control_port` argument to target groups
- Added `mutual_authentication` argument for listeners
- Updated review date

## 3.9.0 - 3rd December 2025

- Added `transform` listener rule
- Bumped Terraform required version due to dependancy requirements

## 3.8.0 - 1st December 2025

- Added `jwt-validation` listener rule
- Fully defined `listener_rules.actions`
- Bumped minimum AWS provider version to `6.22.0`

## 3.7.0 - 14th July 2025

- Added support for header modification in ALB, including the ability to insert the Strict-Transport-Security (HSTS) header. This allows you to configure HSTS directly on your ALB without needing to modify your backend application code.
- Updated the hashicorp/aws provider to version 5.85.0

## 3.6.0 - 12th June 2025

- Added support for TLS 1.3: if listeners.ssl_policy is not explicitly set, it now defaults to `ELBSecurityPolicy-TLS13-1-2-2021-06`

## 3.5.0 - 1st April 2025

- Migrated to use newer `ce-common` module instead of `vars`
- Renamed `warnings.tf` to `checks.tf`

## 3.4.0 - 7th March 2025

- Required terraform version increased to 1.5 to support check blocks.
- Added pre-commit-config file.
- Added warning if logging is not set up. (Wiz VPC-040)
- Added warning if no ACM cert is specified and listener is `HTTPS`. (Wiz ELB-056)
- Added warning if there is a listener with no HTTPS.  (Wiz ELB-047)
- Added warning if TLS < 1.2 is present. (Wiz ELB-010)
- Added warning if healthcheck is not present. (Wiz ELB-051)
- Updated `pre-commit` version to `1.3.0`
- Updated required Terraform version to `1.5`

## 3.3.1 - 1st November 2024

- Updated the hashicorp/aws provider to version 5.69
- Added new added argument `client_keep_alive`

## 3.3.0 - 18th June 2024

- If `target_groups.load_balancing_cross_zone_enabled` is not specifically configured, then it will automatically be set to `false` for resources without an "Environment" tag of value "prd" (and left at the default `use_load_balancer_configuration` otherwise). This is a cost-saving measure. To override this, configure `load_balancing_cross_zone_enabled` in `target_groups` to either `true` or `false`.
- Fix acm module error (due to new version) in test directory

## 3.2.0 - 8th May 2024

- Add `scheme` variable, allowing the ability to deploy an internet-facing load balancer.
- Variable types for `listeners`, `target_groups`, `subnet_mapping` and `listener_rules` have been defined in full.
- Fixed bug that was preventing targets registration.
- Fixed bugs with additional certificates not being applied.
- A number of arguments have moved map variables from `target_groups` to `listeners`, see below.
- Tidied up some default values and conditions.
- Updated variable descriptions.
- Update required AWS provider version to [5.13.0](https://github.com/hashicorp/terraform-provider-aws/blob/main/CHANGELOG.md#5130-august-18-2023), due to `security_groups`.
- Add new output `target_group_names`.

### Migrating to v3.2.0
- The `target_group_index` argument in `listener_rules` has been renamed `target_group_key` for clarity.
- The following arguments have been moved from `target_groups` to `listeners`:
  - `additional_certs`
  - `ssl_policy`
  - `certificate_arn`
- The default value for `access_log_bucket_id` is now `null` instead of `""`.
- The default value for `subnet_ids` is now `[]` instead of `null`.
- Listener certificate attachment has been modified, and may cause existing certificates to be re-deployed to listeners.

## 3.1.2 - 22nd March 2024

- Allow a target group to be created without targets

## 3.1.1 - 26th February 2024

- Fixed Trivy issue: Ignored error around HTTP protocol during test as this is intentional
- Added pre-commit config

## 3.1.0 - 21st December 2023

- Added `fixed-response` and `redirect` options as listener's default action

## 3.0.0 - 5th December 2023

- Fixed issue with target group attachments that were recreated at every change by moving from `count` to `for_each`, and adding a `name` attribute in `targets` to be used as key - ***Please be aware that, if you're upgrading to this version from a previous one, the first time it runs, it will recreate the target attachments!***

## 2.0.4 - 2nd November 2023

- Fixed insecure SSL policy in tests and readme

## 2.0.3 - 1st November 2023

- Add CONTRIBUTING.md

## 2.0.2 - 26th October 2023

- Add benchmark table to README.md

## 2.0.1 - 18th September 2023

- Merge functionality of vars, tagging and label modules

## 2.0.0 - 12th September 2023

- Separated listeners creation from target group (fixing an issue where it was creating one listener per target group. This allows to create a listener with multiple rules and target groups)
- Added option to disable cross-zone LB for specific target groups
- Updated target group name (removed reference to ALB to shorten it, and added `-tg` suffix)

## 1.1.0 - 29th August 2023

- Add tests directory with Jenkinsfile for pull request testing
- Add two test terraform configurations for http and https
- Update cert_list condition to use length as recommended by tflint

## 1.0.1 - 15th August 2023

- Add standard EITS CE tags using eits_vars module
- Update readme to add clarity around listener rules
- Rename conditions to match tf docs
- Fix alb_name validation

## 1.0.0 - 31st July 2023

- Initial release