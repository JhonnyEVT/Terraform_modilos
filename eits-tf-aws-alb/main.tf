locals {
  alb_name = "${var.alb_name}-alb"
  tags     = merge(var.tags, module.eits_ce_common.tags)

  # get a list of additional_certs with their listener
  cert_list = flatten([
    for listener, value in var.listeners : [
      for additional_cert in value.additional_certs : {
        listener = "${lower(value.protocol)}_${value.port}"
        cert_arn = additional_cert
      }
    ]
  ])

  # get a map of targets with their target_group
  target_list = flatten([
    for target_group, value in var.target_groups : [
      for target in value.targets : {
        key               = target.name
        target_group      = target_group
        target_id         = target.target_id
        port              = target.port
        availability_zone = target.availability_zone
      }
    ]
  ])

  # check if the environment is prod
  has_prod_tag = lookup(merge(data.aws_default_tags.this.tags, var.tags), "Environment", "") == "prd"
}

# get provider tags
data "aws_default_tags" "this" {}

module "eits_ce_common" {
  source = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-ce-common.git?ref=v1"

  module_repo = "eits-tf-aws-alb"
  tags        = var.tags
}

resource "aws_lb" "this" {
  name               = local.alb_name
  tags               = merge(local.tags, { Name = local.alb_name })
  internal           = var.scheme == "internal" ? true : false
  load_balancer_type = "application"
  security_groups    = var.security_groups
  subnets            = length(var.subnet_mapping) > 0 || length(var.subnet_ids) == 0 ? null : var.subnet_ids
  client_keep_alive  = var.client_keep_alive

  dynamic "subnet_mapping" {
    for_each = var.subnet_mapping

    content {
      subnet_id            = subnet_mapping.value.subnet_id
      allocation_id        = subnet_mapping.value.allocation_id
      private_ipv4_address = subnet_mapping.value.private_ipv4_address
    }
  }

  ip_address_type            = "ipv4"
  enable_deletion_protection = var.enable_deletion_protection
  desync_mitigation_mode     = var.desync_mitigation_mode
  drop_invalid_header_fields = var.drop_invalid_header_fields
  enable_http2               = var.enable_http2
  enable_xff_client_port     = var.enable_xff_client_port
  enable_waf_fail_open       = var.enable_waf_fail_open
  idle_timeout               = var.idle_timeout
  xff_header_processing_mode = var.xff_header_processing_mode

  enable_tls_version_and_cipher_suite_headers = var.enable_tls_version_and_cipher_suite_headers

  dynamic "access_logs" {
    for_each = var.access_log_bucket_id != null ? [1] : []

    content {
      bucket  = var.access_log_bucket_id
      prefix  = local.alb_name
      enabled = true
    }
  }

  dynamic "connection_logs" {
    for_each = var.connection_logs_bucket_id != null ? [1] : []

    content {
      bucket  = var.connection_logs_bucket_id
      prefix  = local.alb_name
      enabled = true
    }
  }

  dynamic "health_check_logs" {
    for_each = var.health_check_logs_bucket_id != null ? [1] : []

    content {
      bucket  = var.health_check_logs_bucket_id
      prefix  = local.alb_name
      enabled = true
    }
  }
}

resource "aws_lb_target_group" "this" {
  for_each             = var.target_groups
  name                 = "${each.key}-tg" # has 32 character limit, only alphanumeric characters and hyphens allowed
  tags                 = merge(local.tags, { Name = "${var.alb_name}-${each.key}" })
  vpc_id               = each.value.target_type == "lambda" ? null : var.vpc_id
  port                 = each.value.port
  protocol             = each.value.protocol
  protocol_version     = each.value.protocol_version
  target_type          = each.value.target_type
  deregistration_delay = each.value.deregistration_delay
  slow_start           = each.value.slow_start
  preserve_client_ip   = each.value.preserve_client_ip

  load_balancing_cross_zone_enabled  = each.value.load_balancing_cross_zone_enabled != null ? each.value.load_balancing_cross_zone_enabled : local.has_prod_tag ? null : false
  lambda_multi_value_headers_enabled = each.value.lambda_multi_value_headers_enabled
  load_balancing_algorithm_type      = each.value.load_balancing_algorithm_type

  dynamic "health_check" {
    for_each = each.value.health_check != null ? [each.value.health_check] : []

    content {
      enabled             = health_check.value.enabled
      port                = health_check.value.port
      protocol            = health_check.value.protocol
      path                = health_check.value.path
      matcher             = health_check.value.matcher
      healthy_threshold   = health_check.value.healthy_threshold
      unhealthy_threshold = health_check.value.unhealthy_threshold
      interval            = health_check.value.interval
      timeout             = health_check.value.timeout
    }
  }

  dynamic "stickiness" {
    for_each = each.value.stickiness != null ? [each.value.stickiness] : []

    content {
      enabled         = stickiness.value.enabled
      type            = stickiness.value.type
      cookie_name     = stickiness.value.cookie_name
      cookie_duration = stickiness.value.cookie_duration
    }
  }

  lifecycle {
    create_before_destroy = true
  }

}

resource "aws_lb_listener" "this" {
  for_each = { for k, v in var.listeners : "${lower(v.protocol)}_${v.port}" => v }

  load_balancer_arn = aws_lb.this.arn
  port              = each.value.port
  protocol          = each.value.protocol

  ssl_policy      = each.value.ssl_policy == null && each.value.protocol == "HTTPS" ? "ELBSecurityPolicy-TLS13-1-2-2021-06" : each.value.ssl_policy
  certificate_arn = each.value.certificate_arn

  default_action {
    target_group_arn = each.value.fixed_response != null ? null : each.value.redirect != null ? null : each.value.default_target_group != null ? aws_lb_target_group.this[each.value.default_target_group].arn : null
    type             = each.value.fixed_response != null ? "fixed-response" : each.value.redirect != null ? "redirect" : "forward"

    dynamic "fixed_response" {
      for_each = each.value.fixed_response != null ? [each.value.fixed_response] : []
      content {
        content_type = fixed_response.value.content_type
        message_body = fixed_response.value.message_body
        status_code  = fixed_response.value.status_code
      }
    }

    dynamic "redirect" {
      for_each = each.value.redirect != null ? [each.value.redirect] : []
      content {
        port        = redirect.value.port
        protocol    = redirect.value.protocol
        status_code = redirect.value.status_code
      }
    }
  }
  routing_http_response_server_enabled                         = each.value.routing_http_response_server_enabled == null ? false : each.value.routing_http_response_server_enabled
  routing_http_response_strict_transport_security_header_value = each.value.routing_http_response_server_enabled == true ? (each.value.response_hsts_value == null ? "max-age=31536000; includeSubDomains; preload" : each.value.response_hsts_value) : null
  tags                                                         = local.tags
}

resource "aws_lb_listener_certificate" "additional" {
  count = length(local.cert_list)

  listener_arn    = aws_lb_listener.this[local.cert_list[count.index].listener].arn
  certificate_arn = local.cert_list[count.index].cert_arn
}

resource "aws_lb_target_group_attachment" "this" {
  for_each = { for k, v in local.target_list : v.key => v }

  target_group_arn  = aws_lb_target_group.this[each.value.target_group].arn
  target_id         = each.value.target_id
  port              = each.value.port
  availability_zone = each.value.availability_zone
}
