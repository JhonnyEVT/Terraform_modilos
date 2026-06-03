# EITS Cloud Enablement AWS ALB Module

EITS Terraform module for AWS Application Load Balancer. This module will:

- Create an ALB
- Create target groups and associated listeners based on map
- Configure multiple listeners
- Setup listener rules for each listener

See CHANGELOG.md for the list of changes for each release.
*We highly recommend that in your code you pin the version to the exact version you are using so that your infrastructure remains stable, and update versions in a systematic way so that they do not catch you by surprise.*

## EITS Security & Compliance

**Last Module Review**: 2025-12-09

See below for the date and results of our EITS security and compliance scanning.

<!-- BEGIN_BENCHMARK_TABLE -->
| Benchmark | Date | Version | Description |
| --------- | ---- | ------- | ----------- |
| [![tflint](https://img.shields.io/badge/tflint-passed-green)](https://build.experian.local/job/UK-I/job/EITS/job/UKI-Cloud-Enablement/job/terraform-modules/job/eits-tf-aws-alb/130/) | 2025-12-09 | 0.59.1 | Enforces best practices, syntax, naming conventions |
| [![trivy](https://img.shields.io/badge/trivy-passed-green)](https://build.experian.local/job/UK-I/job/EITS/job/UKI-Cloud-Enablement/job/terraform-modules/job/eits-tf-aws-alb/130/) | 2025-12-09 | 0.61.0 | Detects misconfiguration in IaC files, such as Docker, Terraform, etc |
| [![wiz](https://img.shields.io/badge/wiz.io_iac-passed-green)](https://build.experian.local/job/UK-I/job/EITS/job/UKI-Cloud-Enablement/job/terraform-modules/job/eits-tf-aws-alb/130/) | 2025-12-09 | 0.84.0 | Scans tests directory plans for vulnerabilities and risks |
| [![validate](https://img.shields.io/badge/tf_validate-passed-green)](https://build.experian.local/job/UK-I/job/EITS/job/UKI-Cloud-Enablement/job/terraform-modules/job/eits-tf-aws-alb/130/) | 2025-12-09 | 1.14.1 | Validates terraform code using example test directories |
<!-- END_BENCHMARK_TABLE -->

## Resource naming

Due to name character constraints be aware there is a 28 alphanumeric character limit on the `alb_name` variable. This will automatically be suffixed with '-alb'.

## Listener Rules

ALB listener rules are configured using the `listener_rules` variable, this is a list of maps and is an optional keyword. The variable is constructed in a specific way in order to offer flexibility. Some notes on how to use this:

- See [lb_listener_rules](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) for details on required arguments and values.
- It requires to specify to which listener you want to associate the rule to.
- It accepts both an `actions` and `conditions` list. To set no conditions, either omit the argument or pass an empty list `[]`.
- To add more listener rules, add more elements to the root `listener_rules` list.

For example:

```hcl
listeners = [
  {
    port                 = 443
    protocol             = "HTTPS"
    default_target_group = "tg1" # Must match an existing target group, which will be used as a default target. Multiple can be created associated with different rules
    ssl_policy           = "ELBSecurityPolicy-TLS13-1-2-2021-06"
    certificate_arn      = "arn:aws:iam::123456789012:server-certificate/cert_name"
  }
]
```
**Note:**  
## If `ssl_policy` is not specified for a listener, it will default to `ELBSecurityPolicy-TLS13-1-2-2021-06` (TLS 1.3).

```hcl
listener_rules = [
  {
    listener         = "https_443" # must match the listener in the format of (all lowercase) protocol_port
    target_group_key = "tg1"
    priority         = 1
    actions = [
      {
        # see below for example
      }
    ]
    conditions = [
      {
        # see below for example
      }
    ]
    transforms = [
      {
        # see below for example
      }
    ]
  },
  {
    # additional rules here
  }
]
```

### Actions

Valid `actions` `type` are `forward`, `redirect`, `fixed-response`, `authenticate-cognito`, `authenticate-oidc`, `jwt-validation` . 
The key/values in this map will be equal to those required in [lb_listener_rules](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule). Pass actions as a list of maps, for example:

```hcl
actions = [
  {
    type = "forward"
    target_groups = [
      {
        target_group_key = "tg1"
        weight           = 1
      }
    ]
    stickiness = {
      enabled  = true
      duration = 3600
    }
  }
]
```

### Conditions

Pass conditions as a list of maps, these maps must be named one of `host_header`, `http_header`, `http_request_method`, `path_pattern`, `query_string` or `source_ip`. Within this map is a further list, you may supply multiple elements to add fither conditions of the same type. For example here is a query_string condition:

```hcl
 conditions = [
  {
    query_string = [
      {
        key   = "weighted"
        value = "true"
      },
      {
        key   = "health"
        value = "check"
      }
    ]
  }
]
```

### Transforms

Valid `transforms` `type` are `url-rewrite` and `host-header-rewrite`.
You will require both `regex` and `replace` to be specified for the pattern match to perform the rewrite on and the transform for when the pattern matches. Transforms are optional and not required for a successful deployment.

```hcl
transforms = [
  {
    type    = "url-rewrite"
    regex   = "/old-path/(.*)"
    replace = "/new-path/$1"
  }
]
```

## Other notes

- All new ELBs are internal in accordance with EEC guidelines
- IPv6 is not supported in this module, if it is actually required we can add it
- Cross-zone load balancing is always on for Application Load Balancers. However, if `target_groups.load_balancing_cross_zone_enabled` is not specifically configured, then it will automatically be set to `false` for resources without an "Environment" tag of value "prd" (and left at the default `use_load_balancer_configuration` otherwise). This is a cost-saving measure. To override this, configure `load_balancing_cross_zone_enabled` in `target_groups` to either `true` or `false`.
- Some target group arguments are only/not applicable to lambda targets, see [lb_target_group](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) for details
- Listeners are automatically named `protocol_port` (lowercase, e.g. `https_443`). This is unique as you can't have multiple listeners on the same protocol and port
- The `targets` attribute in `target_groups` require the attribute `name` so that the target is uniquely identified, and won't be removed if other targets are added or removed. **This must be a static value, it can't be dynamically generated**
- The listener default action can be configured as one of `fixed_response`, `redirect`, or `default_target_group`. Only one of the 3 should be configured:
  - `fixed_response`. Required argument: `content_type` (Valid values are `text/plain`, `text/css`, `text/html`, `application/javascript`, and `application/json`). Optional arguments: `message_body`, and `status_code` (Valid values are `2XX`, `4XX`, or `5XX`.)
  - `redirect`. Required argument: `status_code` (Either permanent `HTTP_301` or temporary `HTTP_302`). Optional arguments: `port`, `protocol`, `host`, `path`, `query`
  - `default_target_group`. Requires a set of 1-5 target group blocks
- The `additional_certs` attribute in `listeners` allows you to attach a list of ACM certificate ARNS to the listener
- Adding or removing `security_groups` to an already existing NLB will cause the resource to be recreated

## Notes about HSTS headers
- The HSTS header functionality is part of [AWS Application Load Balancer's header modification feature](https://aws.amazon.com/about-aws/whats-new/2024/11/aws-application-load-balancer-header-modification-enhanced-traffic-control-security/) introduced in November 2024. As a relatively new feature, it may have some implementation issues.
- Due to a [known issue in the AWS provider](https://github.com/hashicorp/terraform-provider-aws/issues/43042), setting `routing_http_response_server_enabled = false` and `response_hsts_value = null` or empty string will still keep HSTS header that was set. This behavior will be fixed in future AWS provider versions.
- By default, ALB only adds custom headers, including the Strict-Transport-Security (HSTS) header, to successful responses (typically 2xx and 3xx status codes)**HTTP and HTTPS Protocol only**. This behavior is not specific to Terraform but is a characteristic of the ALB itself. For more information, see [this AWS re:Post discussion](https://repost.aws/questions/QUXxH0XLpdQX-9ZJPU_-Ovig/alb-listener-attributes-headers-missing-in-non-2xx-responses).

## Usage

### Example of HTTP ALB with IP Address Targets

```hcl
module "alb" {
  source  = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-alb.git"

  alb_name             = "<used for naming resources>"
  vpc_id               = "<vpc id to associate with alb>"
  subnet_ids           = [ <list of subnet IDs, at least 2 in different az> ]
  security_groups      = [ <list of security group ids> ]
  access_log_bucket_id = "<optional s3 bucket id for logging>"

  # a map of maps for each required target group. the root key of each map will be used for naming resources
  target_groups = {
    tg1 = {
      port        = 80
      protocol    = "HTTP"
      target_type = "ip"
			
      # a list of maps for each target
      targets = [
        {
          name              = "<target_name>"
          target_id         = "<ip address>"
          availability_zone = "<required if ip is not in local vpc>"
        }
      ]
    }
  }

  # use root key from target_groups for default_target_group
  listeners = [
    {
      port                 = 443
      protocol             = "HTTPS"
      default_target_group = "tg1"
      ssl_policy           = "ELBSecurityPolicy-TLS13-1-2-2021-06"
      certificate_arn      = "arn:aws:iam::123456789012:server-certificate/cert_name"
    },
    {
      port     = 80
      protocol = "HTTP"
      fixed_response = {
        content_type = "text/plain"
        message_body = "HTTP Unupported"
        status_code  = "400"
      }
    }
  ]

  # listener rules are configured using the listener_rules list of maps, this key is optional, see above
  listener_rules = [
    {
      listener         = "https_443"
      target_group_key = "tg1"
      priority         = 1
      actions = [
        {
          type = "forward"
          target_groups = [
            {
              target_group_key = "tg1"
              weight           = 1
            }
          ]
        }
      ]
      conditions = [
        {
          query_strings = [
            {
              key   = "weighted"
              value = "true"
            }
          ]
        }
      ]
    }
  ]

  # note: name tag is automatically added
  tags = {
    Environment = <env>
    CostString  = <CostString>
    AppID       = <AppID>
  }
}
```

### Example of HTTPS ALB with EC2 Instance Targets

```hcl
module "alb" {
  source = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-alb.git"

  alb_name        = "<used for naming resources>"
  vpc_id          = "<vpc id to associate with alb>"
  subnet_ids      = [ <list of subnet IDs, at least 2 in different az> ]
  security_groups = [ <list of security group ids> ]

  # a map of maps for each required target group. the root key of each map will be used for naming resources
  target_groups = {
    tg1 = {
      port            = 443
      protocol        = "HTTPS"
      target_type     = "instance"

      # health_check is an optional map
      health_check = {
        enabled = true
        port    = <traffic port>
      }

      # a list of maps for each target
      targets = [
        {
          name      = "<target_name>"
          target_id = "<ec2 instance id>"
          port      = <target port> # Optional, if different from the target group port to redirect traffic to a different port
        }
      ]
    }
  }

  # use root key from target_groups for default_target_group
  listeners = [
    {
      port                 = 443
      protocol             = "HTTPS"
      default_target_group = "tg1"
      ssl_policy           = "ELBSecurityPolicy-TLS13-1-2-2021-06"
      certificate_arn      = "arn:aws:iam::123456789012:server-certificate/cert_name"
    },
    {
      port     = 80
      protocol = "HTTP"
      redirect = {
        port         = "443"
        protocol     = "HTTPS"
        status_code  = "HTTP_301"
      }
    }
  ]

  # listener rules are configured using the listener_rules list of maps, this key is optional, see above
  listener_rules = [
    {
      listener         = "https_443"
      target_group_key = "tg1"
      priority         = 1
      actions = [
        {
          type = "forward"
          target_groups = [
            {
              target_group_key = "tg1"
              weight           = 1
            }
          ]
        }
      ]
      conditions = [
        {
          host_header = ["exampledomain.com"]
        },
        {
          path_pattern = ["/examplepath1/*", "/examplepath2/*"]
        }
      ]
      tags = {
        Name = "example"
      }
    }
  ]

  # note: name tag is automatically added
  tags = {
    Environment = "<env>"
    CostString  = "<CostString>"
    AppID       = "<AppID>"
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.9 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.25.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 6.25.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_eits_ce_common"></a> [eits\_ce\_common](#module\_eits\_ce\_common) | git::https://code.experian.local/scm/EUCES/eits-tf-aws-ce-common.git | v1 |

## Resources

| Name | Type |
|------|------|
| [aws_lb.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb) | resource |
| [aws_lb_listener.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener) | resource |
| [aws_lb_listener_certificate.additional](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_certificate) | resource |
| [aws_lb_listener_rule.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) | resource |
| [aws_lb_target_group.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group) | resource |
| [aws_lb_target_group_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group_attachment) | resource |
| [aws_default_tags.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/default_tags) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_access_log_bucket_id"></a> [access\_log\_bucket\_id](#input\_access\_log\_bucket\_id) | The S3 bucket name to store the access logs in. If `null`, then access logs will not be enabled | `string` | `null` | no |
| <a name="input_alb_name"></a> [alb\_name](#input\_alb\_name) | Used to name all resources, must be unique per account | `string` | n/a | yes |
| <a name="input_client_keep_alive"></a> [client\_keep\_alive](#input\_client\_keep\_alive) | Client keep alive value in seconds. The valid range is 60-604800 seconds. The default is 3600 seconds | `number` | `3600` | no |
| <a name="input_connection_logs_bucket_id"></a> [connection\_logs\_bucket\_id](#input\_connection\_logs\_bucket\_id) | The S3 bucket name to store the connection logs in. If `null`, then connection logs will not be enabled | `string` | `null` | no |
| <a name="input_desync_mitigation_mode"></a> [desync\_mitigation\_mode](#input\_desync\_mitigation\_mode) | How the ALP handles HTTP desync requests. Valid values are `monitor`, `defensive`, `strictest` | `string` | `"defensive"` | no |
| <a name="input_drop_invalid_header_fields"></a> [drop\_invalid\_header\_fields](#input\_drop\_invalid\_header\_fields) | Whether HTTP headers with header fields that are not valid are removed by the load balancer `true` or routed to targets `false`<br/>Invalid headers being passed through to the target of the load balance may exploit vulnerabilities, set to `true` by default. | `bool` | `true` | no |
| <a name="input_enable_deletion_protection"></a> [enable\_deletion\_protection](#input\_enable\_deletion\_protection) | A boolean flag to enable/disable deletion protection for ALB | `bool` | `true` | no |
| <a name="input_enable_http2"></a> [enable\_http2](#input\_enable\_http2) | Whether HTTP/2 is enabled | `bool` | `true` | no |
| <a name="input_enable_tls_version_and_cipher_suite_headers"></a> [enable\_tls\_version\_and\_cipher\_suite\_headers](#input\_enable\_tls\_version\_and\_cipher\_suite\_headers) | Whether the two headers (x-amzn-tls-version and x-amzn-tls-cipher-suite) are added to the client request before sending it to the target | `bool` | `false` | no |
| <a name="input_enable_waf_fail_open"></a> [enable\_waf\_fail\_open](#input\_enable\_waf\_fail\_open) | Whether to allow a WAF-enabled load balancer to route requests to targets if it is unable to forward the request to AWS WAF | `bool` | `false` | no |
| <a name="input_enable_xff_client_port"></a> [enable\_xff\_client\_port](#input\_enable\_xff\_client\_port) | Whether the X-Forwarded-For header should preserve the source port that the client used to connect to the load balancer | `bool` | `false` | no |
| <a name="input_health_check_logs_bucket_id"></a> [health\_check\_logs\_bucket\_id](#input\_health\_check\_logs\_bucket\_id) | The S3 bucket name to store the health check logs in. If `null`, then health check logs will not be enabled | `string` | `null` | no |
| <a name="input_idle_timeout"></a> [idle\_timeout](#input\_idle\_timeout) | The time in seconds that the connection is allowed to be idle. | `number` | `60` | no |
| <a name="input_listener_rules"></a> [listener\_rules](#input\_listener\_rules) | A list of maps describing the listener rules for this ALB. <br/>  Use `listener` argument to attach rule to a listener, this must match protocol and port of the required listener in the format `<protocol>_<port>` (all lowercase, e.g. `https_443`). <br/>  Use `target_group_key` to reference a target group in required, must match required root key from 'target\_groups'. <br/>  Valid `actions` `type` are: pre-routing: `authenticate-cognito`, `authenticate-oidc`, `jwt-validation`; routing: `forward`, `redirect`, `fixed-response`. Note that you can configure up to one type per action.<br/>  See [lb\_listener\_rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) for compatible action and conditions blocks. <br/>  See README.md for more examples | <pre>list(object({<br/>    listener         = optional(string)<br/>    target_group_key = optional(string)<br/>    priority         = optional(number)<br/>    actions = optional(list(object({<br/>      type = string<br/>      # Pre-routing action attributes<br/>      additional_claims = optional(list(object({<br/>        format = string<br/>        name   = string<br/>        values = list(string)<br/>      })), [])<br/>      authentication_request_extra_params = optional(map(string))<br/>      authorization_endpoint              = optional(string)<br/>      client_id                           = optional(string)<br/>      client_secret                       = optional(string)<br/>      issuer                              = optional(string)<br/>      jwks_endpoint                       = optional(string)<br/>      on_unauthenticated_request          = optional(string)<br/>      scope                               = optional(string)<br/>      session_cookie_name                 = optional(string)<br/>      session_timeout                     = optional(number)<br/>      token_endpoint                      = optional(string)<br/>      user_pool_arn                       = optional(string)<br/>      user_pool_client_id                 = optional(string)<br/>      user_pool_domain                    = optional(string)<br/>      user_info_endpoint                  = optional(string)<br/>      # Routing action attributes<br/>      content_type = optional(string)<br/>      host         = optional(string)<br/>      message_body = optional(string)<br/>      path         = optional(string)<br/>      port         = optional(number)<br/>      protocol     = optional(string)<br/>      query        = optional(string)<br/>      status_code  = optional(string)<br/>      stickiness = optional(object({<br/>        enabled  = bool<br/>        duration = number<br/>      }))<br/>      target_group_arn = optional(string)<br/>      target_groups = optional(list(object({<br/>        weight = number<br/>      })), [])<br/>    })), [])<br/>    conditions = optional(list(any), [])<br/>    transforms = optional(list(object({<br/>      type    = string<br/>      regex   = string<br/>      replace = string<br/>    })), [])<br/>    tags = optional(map(string), {})<br/>  }))</pre> | `[]` | no |
| <a name="input_listeners"></a> [listeners](#input\_listeners) | A list of maps describing the listeners for this ALB. Use `default_target_group` to attach listener to a target group, must match required root key from 'target\_groups'. If neither `fixed_response` or `redirect` arguments are passed, then listener will default to `forward` action. See [lb\_listener](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener#argument-reference) for argument reference and required values | <pre>list(object({<br/>    default_target_group = optional(string)<br/>    port                 = optional(number)<br/>    protocol             = optional(string)<br/>    ssl_policy           = optional(string)<br/>    certificate_arn      = optional(string)<br/>    additional_certs     = optional(list(string), [])<br/>    fixed_response = optional(object({<br/>      content_type = optional(string)<br/>      message_body = optional(string)<br/>      status_code  = optional(string)<br/>    }))<br/>    redirect = optional(object({<br/>      port        = optional(number)<br/>      protocol    = optional(string)<br/>      status_code = optional(string)<br/>    }))<br/>    routing_http_response_server_enabled = optional(bool)<br/>    response_hsts_value                  = optional(string)<br/>    mutual_authentication = optional(object({<br/>      advertise_trust_store_ca_names   = optional(string)<br/>      ignore_client_certificate_expiry = optional(bool)<br/>      mode                             = string<br/>      trust_store_arn                  = optional(string)<br/>    }))<br/>  }))</pre> | `[]` | no |
| <a name="input_scheme"></a> [scheme](#input\_scheme) | The load balancer scheme, either `internet-facing` or `internal`. The nodes of an internet-facing (or 'public') load balancer have public IP addresses. The nodes of an internal load balancer have only private IP addresses. It is recommended to use an internal load balancer unless your usecase specifically requires an internet-facing one. Defaults to `internal` | `string` | `"internal"` | no |
| <a name="input_security_groups"></a> [security\_groups](#input\_security\_groups) | A list of security group IDs to assign to the ALB. Security groups cannot be added if none are currently present, and cannot all be removed once added. Either of these conditions will force a recreation of the ALB resource | `list(string)` | `[]` | no |
| <a name="input_subnet_ids"></a> [subnet\_ids](#input\_subnet\_ids) | A list of subnet IDs to associate with NLB. Will be ignored if `subnet_mapping` is populated | `list(string)` | `[]` | no |
| <a name="input_subnet_mapping"></a> [subnet\_mapping](#input\_subnet\_mapping) | A list of maps describing subnets to attach to load balancer. Will override `subnet_ids` if populated. Note: at least two subnets in two different Availability Zones must be specified | <pre>list(object({<br/>    subnet_id            = optional(string)<br/>    allocation_id        = optional(string)<br/>    private_ipv4_address = optional(string)<br/>  }))</pre> | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags for AWS resources. See [Cloud Tagging Strategy & Standards](https://pages.experian.com/pages/viewpage.action?pageId=400041906) for available tags | `map(string)` | `{}` | no |
| <a name="input_target_groups"></a> [target\_groups](#input\_target\_groups) | A map of maps for each required target group. The root map keys must be unique identifiers for each target group map, this will also be used to name the target groups. See [lb\_target\_group resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group#argument-reference) for valid/default values | <pre>map(object({<br/>    port                               = optional(number)<br/>    protocol                           = optional(string)<br/>    protocol_version                   = optional(string)<br/>    deregistration_delay               = optional(number)<br/>    slow_start                         = optional(number)<br/>    preserve_client_ip                 = optional(bool)<br/>    load_balancing_cross_zone_enabled  = optional(bool)<br/>    lambda_multi_value_headers_enabled = optional(bool)<br/>    load_balancing_algorithm_type      = optional(string)<br/>    target_control_port                = optional(number)<br/>    health_check = optional(object({<br/>      enabled             = optional(bool)<br/>      port                = optional(any)<br/>      protocol            = optional(string)<br/>      path                = optional(string)<br/>      matcher             = optional(string)<br/>      healthy_threshold   = optional(number)<br/>      unhealthy_threshold = optional(number)<br/>      interval            = optional(number)<br/>      timeout             = optional(number)<br/>    }))<br/>    stickiness = optional(object({<br/>      enabled         = optional(bool)<br/>      type            = optional(string)<br/>      cookie_name     = optional(string)<br/>      cookie_duration = optional(number)<br/>    }))<br/>    target_type = optional(string)<br/>    targets = optional(list(object({<br/>      name              = optional(string)<br/>      target_id         = optional(string)<br/>      port              = optional(number)<br/>      availability_zone = optional(string)<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_vpc_id"></a> [vpc\_id](#input\_vpc\_id) | VPC ID to associate with ALB | `string` | n/a | yes |
| <a name="input_xff_header_processing_mode"></a> [xff\_header\_processing\_mode](#input\_xff\_header\_processing\_mode) | Determines how the ALB modifies the X-Forwarded-For header in the HTTP request before sending the request to the target. Valid values are `append`, `preserve`, `remove` | `string` | `"append"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alb_arn"></a> [alb\_arn](#output\_alb\_arn) | The ARN of the ALB |
| <a name="output_alb_dns_name"></a> [alb\_dns\_name](#output\_alb\_dns\_name) | DNS name of ALB |
| <a name="output_alb_name"></a> [alb\_name](#output\_alb\_name) | The ARN suffix of the ALB |
| <a name="output_alb_zone_id"></a> [alb\_zone\_id](#output\_alb\_zone\_id) | The ID of the zone which ALB is provisioned |
| <a name="output_listener_arns"></a> [listener\_arns](#output\_listener\_arns) | A list of all the listener ARNs |
| <a name="output_target_group_arns"></a> [target\_group\_arns](#output\_target\_group\_arns) | A list of all the target group ARNs |
| <a name="output_target_group_names"></a> [target\_group\_names](#output\_target\_group\_names) | A list of all the target group names |
<!-- END_TF_DOCS -->

## Metadata

```discoveryhub
summary: Terraform module for AWS Application Load Balancer (ALB)
region: Global
bu: EITS
contacts:
  technical: EITS UK&I Cloud Enablement Team eitsukicloud@experian.com
```
