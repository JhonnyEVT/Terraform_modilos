variable "access_log_bucket_id" {
  type        = string
  default     = null
  description = "The S3 bucket name to store the access logs in. If `null`, then access logs will not be enabled"
}

variable "connection_logs_bucket_id" {
  type        = string
  default     = null
  description = "The S3 bucket name to store the connection logs in. If `null`, then connection logs will not be enabled"
}

variable "health_check_logs_bucket_id" {
  type        = string
  default     = null
  description = "The S3 bucket name to store the health check logs in. If `null`, then health check logs will not be enabled"
}

variable "alb_name" {
  type        = string
  description = "Used to name all resources, must be unique per account"

  validation {
    condition = (
      can(regex("^[a-zA-Z0-9-]{1,28}$", var.alb_name))
    )
    error_message = "The alb_name variable must have a maximum of 28 alphanumerical characters"
  }
}

variable "client_keep_alive" {
  type        = number
  default     = 3600
  description = "Client keep alive value in seconds. The valid range is 60-604800 seconds. The default is 3600 seconds"
}

variable "desync_mitigation_mode" {
  type        = string
  default     = "defensive"
  description = "How the ALP handles HTTP desync requests. Valid values are `monitor`, `defensive`, `strictest`"
}

variable "drop_invalid_header_fields" {
  type        = bool
  default     = true
  description = <<-EOT
    Whether HTTP headers with header fields that are not valid are removed by the load balancer `true` or routed to targets `false`
    Invalid headers being passed through to the target of the load balance may exploit vulnerabilities, set to `true` by default.
    EOT
}

variable "enable_deletion_protection" {
  type        = bool
  default     = true
  description = "A boolean flag to enable/disable deletion protection for ALB"
}

variable "enable_http2" {
  type        = bool
  default     = true
  description = "Whether HTTP/2 is enabled"
}

variable "enable_tls_version_and_cipher_suite_headers" {
  type        = bool
  default     = false
  description = "Whether the two headers (x-amzn-tls-version and x-amzn-tls-cipher-suite) are added to the client request before sending it to the target"
}

variable "enable_xff_client_port" {
  type        = bool
  default     = false
  description = "Whether the X-Forwarded-For header should preserve the source port that the client used to connect to the load balancer"
}

variable "enable_waf_fail_open" {
  type        = bool
  default     = false
  description = "Whether to allow a WAF-enabled load balancer to route requests to targets if it is unable to forward the request to AWS WAF"
}

variable "idle_timeout" {
  type        = number
  default     = 60
  description = "The time in seconds that the connection is allowed to be idle."
}

variable "listeners" {
  type = list(object({
    default_target_group = optional(string)
    port                 = optional(number)
    protocol             = optional(string)
    ssl_policy           = optional(string)
    certificate_arn      = optional(string)
    additional_certs     = optional(list(string), [])
    fixed_response = optional(object({
      content_type = optional(string)
      message_body = optional(string)
      status_code  = optional(string)
    }))
    redirect = optional(object({
      port        = optional(number)
      protocol    = optional(string)
      status_code = optional(string)
    }))
    routing_http_response_server_enabled = optional(bool)
    response_hsts_value                  = optional(string)
    mutual_authentication = optional(object({
      advertise_trust_store_ca_names   = optional(string)
      ignore_client_certificate_expiry = optional(bool)
      mode                             = string
      trust_store_arn                  = optional(string)
    }))
  }))
  default     = []
  description = "A list of maps describing the listeners for this ALB. Use `default_target_group` to attach listener to a target group, must match required root key from 'target_groups'. If neither `fixed_response` or `redirect` arguments are passed, then listener will default to `forward` action. See [lb_listener](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener#argument-reference) for argument reference and required values"
}

variable "listener_rules" {
  type = list(object({
    listener         = optional(string)
    target_group_key = optional(string)
    priority         = optional(number)
    actions = optional(list(object({
      type = string
      # Pre-routing action attributes
      additional_claims = optional(list(object({
        format = string
        name   = string
        values = list(string)
      })), [])
      authentication_request_extra_params = optional(map(string))
      authorization_endpoint              = optional(string)
      client_id                           = optional(string)
      client_secret                       = optional(string)
      issuer                              = optional(string)
      jwks_endpoint                       = optional(string)
      on_unauthenticated_request          = optional(string)
      scope                               = optional(string)
      session_cookie_name                 = optional(string)
      session_timeout                     = optional(number)
      token_endpoint                      = optional(string)
      user_pool_arn                       = optional(string)
      user_pool_client_id                 = optional(string)
      user_pool_domain                    = optional(string)
      user_info_endpoint                  = optional(string)
      # Routing action attributes
      content_type = optional(string)
      host         = optional(string)
      message_body = optional(string)
      path         = optional(string)
      port         = optional(number)
      protocol     = optional(string)
      query        = optional(string)
      status_code  = optional(string)
      stickiness = optional(object({
        enabled  = bool
        duration = number
      }))
      target_group_arn = optional(string)
      target_groups = optional(list(object({
        weight = number
      })), [])
    })), [])
    conditions = optional(list(any), [])
    transforms = optional(list(object({
      type    = string
      regex   = string
      replace = string
    })), [])
    tags = optional(map(string), {})
  }))
  default     = []
  description = <<EOT
  A list of maps describing the listener rules for this ALB. 
  Use `listener` argument to attach rule to a listener, this must match protocol and port of the required listener in the format `<protocol>_<port>` (all lowercase, e.g. `https_443`). 
  Use `target_group_key` to reference a target group in required, must match required root key from 'target_groups'. 
  Valid `actions` `type` are: pre-routing: `authenticate-cognito`, `authenticate-oidc`, `jwt-validation`; routing: `forward`, `redirect`, `fixed-response`. Note that you can configure up to one type per action.
  See [lb_listener_rule](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_listener_rule) for compatible action and conditions blocks. 
  See README.md for more examples
  EOT
}

variable "scheme" {
  type        = string
  default     = "internal"
  description = "The load balancer scheme, either `internet-facing` or `internal`. The nodes of an internet-facing (or 'public') load balancer have public IP addresses. The nodes of an internal load balancer have only private IP addresses. It is recommended to use an internal load balancer unless your usecase specifically requires an internet-facing one. Defaults to `internal`"
}

variable "security_groups" {
  type        = list(string)
  default     = []
  description = "A list of security group IDs to assign to the ALB. Security groups cannot be added if none are currently present, and cannot all be removed once added. Either of these conditions will force a recreation of the ALB resource"
}

variable "subnet_ids" {
  type        = list(string)
  default     = []
  description = "A list of subnet IDs to associate with NLB. Will be ignored if `subnet_mapping` is populated"
}

variable "subnet_mapping" {
  type = list(object({
    subnet_id            = optional(string)
    allocation_id        = optional(string)
    private_ipv4_address = optional(string)
  }))
  default     = []
  description = "A list of maps describing subnets to attach to load balancer. Will override `subnet_ids` if populated. Note: at least two subnets in two different Availability Zones must be specified"
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags for AWS resources. See [Cloud Tagging Strategy & Standards](https://pages.experian.com/pages/viewpage.action?pageId=400041906) for available tags"
}

variable "target_groups" {
  type = map(object({
    port                               = optional(number)
    protocol                           = optional(string)
    protocol_version                   = optional(string)
    deregistration_delay               = optional(number)
    slow_start                         = optional(number)
    preserve_client_ip                 = optional(bool)
    load_balancing_cross_zone_enabled  = optional(bool)
    lambda_multi_value_headers_enabled = optional(bool)
    load_balancing_algorithm_type      = optional(string)
    target_control_port                = optional(number)
    health_check = optional(object({
      enabled             = optional(bool)
      port                = optional(any)
      protocol            = optional(string)
      path                = optional(string)
      matcher             = optional(string)
      healthy_threshold   = optional(number)
      unhealthy_threshold = optional(number)
      interval            = optional(number)
      timeout             = optional(number)
    }))
    stickiness = optional(object({
      enabled         = optional(bool)
      type            = optional(string)
      cookie_name     = optional(string)
      cookie_duration = optional(number)
    }))
    target_type = optional(string)
    targets = optional(list(object({
      name              = optional(string)
      target_id         = optional(string)
      port              = optional(number)
      availability_zone = optional(string)
    })), [])
  }))
  default     = {}
  description = "A map of maps for each required target group. The root map keys must be unique identifiers for each target group map, this will also be used to name the target groups. See [lb_target_group resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/lb_target_group#argument-reference) for valid/default values"
}

variable "vpc_id" {
  type        = string
  description = "VPC ID to associate with ALB"
}

variable "xff_header_processing_mode" {
  type        = string
  default     = "append"
  description = "Determines how the ALB modifies the X-Forwarded-For header in the HTTP request before sending the request to the target. Valid values are `append`, `preserve`, `remove`"
}
