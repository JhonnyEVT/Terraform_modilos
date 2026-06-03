/*
    listener rules have been seperated from the main terraform resources due to complexity
    they are deployed using the listener_rules variable, see README.md for details
*/

resource "aws_lb_listener_rule" "this" {
  count = length(var.listener_rules)

  listener_arn = aws_lb_listener.this[var.listener_rules[count.index].listener].arn
  priority     = var.listener_rules[count.index].priority

  # authenticate-cognito actions
  dynamic "action" {
    for_each = [
      for action_rule in var.listener_rules[count.index].actions :
      action_rule
      if action_rule.type == "authenticate-cognito"
    ]

    content {
      type = action.value["type"]
      authenticate_cognito {
        authentication_request_extra_params = lookup(action.value, "authentication_request_extra_params", null)
        on_unauthenticated_request          = lookup(action.value, "on_authenticated_request", null)
        scope                               = lookup(action.value, "scope", null)
        session_cookie_name                 = lookup(action.value, "session_cookie_name", null)
        session_timeout                     = lookup(action.value, "session_timeout", null)
        user_pool_arn                       = action.value["user_pool_arn"]
        user_pool_client_id                 = action.value["user_pool_client_id"]
        user_pool_domain                    = action.value["user_pool_domain"]
      }
    }
  }

  # authenticate-oidc actions
  dynamic "action" {
    for_each = [
      for action_rule in var.listener_rules[count.index].actions :
      action_rule
      if action_rule.type == "authenticate-oidc"
    ]

    content {
      type = action.value["type"]
      authenticate_oidc {
        # Max 10 extra params
        authentication_request_extra_params = lookup(action.value, "authentication_request_extra_params", null)
        authorization_endpoint              = action.value["authorization_endpoint"]
        client_id                           = action.value["client_id"]
        client_secret                       = action.value["client_secret"]
        issuer                              = action.value["issuer"]
        on_unauthenticated_request          = lookup(action.value, "on_unauthenticated_request", null)
        scope                               = lookup(action.value, "scope", null)
        session_cookie_name                 = lookup(action.value, "session_cookie_name", null)
        session_timeout                     = lookup(action.value, "session_timeout", null)
        token_endpoint                      = action.value["token_endpoint"]
        user_info_endpoint                  = action.value["user_info_endpoint"]
      }
    }
  }

  # JWT validation
  dynamic "action" {
    for_each = [
      for action_rule in var.listener_rules[count.index].actions :
      action_rule
      if action_rule.type == "jwt-validation"
    ]

    content {
      type = action.value["type"]
      jwt_validation {
        issuer        = action.value["issuer"]
        jwks_endpoint = action.value["jwks_endpoint"]
        dynamic "additional_claim" {
          for_each = lookup(action.value, "additional_claims", [])

          content {
            format = additional_claim.value["format"]
            name   = additional_claim.value["name"]
            values = additional_claim.value["values"]
          }
        }
      }
    }
  }

  # redirect actions
  dynamic "action" {
    for_each = [
      for action_rule in var.listener_rules[count.index].actions :
      action_rule
      if action_rule.type == "redirect"
    ]

    content {
      type = action.value["type"]
      redirect {
        host        = lookup(action.value, "host", null)
        path        = lookup(action.value, "path", null)
        port        = lookup(action.value, "port", null)
        protocol    = lookup(action.value, "protocol", null)
        query       = lookup(action.value, "query", null)
        status_code = action.value["status_code"]
      }
    }
  }

  # fixed-response actions
  dynamic "action" {
    for_each = [
      for action_rule in var.listener_rules[count.index].actions :
      action_rule
      if action_rule.type == "fixed-response"
    ]

    content {
      type = action.value["type"]
      fixed_response {
        message_body = lookup(action.value, "message_body", null)
        status_code  = lookup(action.value, "status_code", null)
        content_type = action.value["content_type"]
      }
    }
  }

  # forward actions
  dynamic "action" {
    for_each = [
      for action_rule in var.listener_rules[count.index].actions :
      action_rule
      if action_rule.type == "forward"
    ]

    content {
      type             = action.value["type"]
      target_group_arn = aws_lb_target_group.this[var.listener_rules[count.index].target_group_key].id
    }
  }

  # weighted forward actions
  dynamic "action" {
    for_each = [
      for action_rule in var.listener_rules[count.index].actions :
      action_rule
      if action_rule.type == "weighted-forward"
    ]

    content {
      type = "forward"
      forward {
        dynamic "target_group" {
          for_each = action.value["target_groups"]

          content {
            arn    = aws_lb_target_group.this[var.listener_rules[count.index].target_group_key].id
            weight = target_group.value["weight"]
          }
        }
        dynamic "stickiness" {
          for_each = [lookup(action.value, "stickiness", {})]

          content {
            enabled  = try(stickiness.value["enabled"], false)
            duration = try(stickiness.value["duration"], 1)
          }
        }
      }
    }
  }

  # URL Rewrite Transform
  dynamic "transform" {
    for_each = [
      for transform_rule in var.listener_rules[count.index].transforms :
      transform_rule
      if transform_rule.type == "url-rewrite"
    ]

    content {
      type = "url-rewrite"
      url_rewrite_config {
        rewrite {
          regex   = transform.value["regex"]
          replace = transform.value["replace"]
        }
      }
    }
  }

  # Host Header Rewrite Transform
  dynamic "transform" {
    for_each = [
      for transform_rule in var.listener_rules[count.index].transforms :
      transform_rule
      if transform_rule.type == "host-header-rewrite"
    ]

    content {
      type = "host-header-rewrite"
      url_rewrite_config {
        rewrite {
          regex   = transform.value["regex"]
          replace = transform.value["replace"]
        }
      }
    }
  }

  # Path Pattern condition
  dynamic "condition" {
    for_each = [
      for condition_rule in var.listener_rules[count.index].conditions :
      condition_rule
      if length(lookup(condition_rule, "path_pattern", [])) > 0
    ]

    content {
      path_pattern {
        values = condition.value["path_pattern"]
      }
    }
  }

  # Host header condition
  dynamic "condition" {
    for_each = [
      for condition_rule in var.listener_rules[count.index].conditions :
      condition_rule
      if length(lookup(condition_rule, "host_header", [])) > 0
    ]

    content {
      host_header {
        values = condition.value["host_header"]
      }
    }
  }

  # Http header condition
  dynamic "condition" {
    for_each = [
      for condition_rule in var.listener_rules[count.index].conditions :
      condition_rule
      if length(lookup(condition_rule, "http_header", [])) > 0
    ]

    content {
      dynamic "http_header" {
        for_each = condition.value["http_header"]

        content {
          http_header_name = http_header.value["http_header_name"]
          values           = http_header.value["values"]
        }
      }
    }
  }

  # Http request method condition
  dynamic "condition" {
    for_each = [
      for condition_rule in var.listener_rules[count.index].conditions :
      condition_rule
      if length(lookup(condition_rule, "http_request_method", [])) > 0
    ]

    content {
      http_request_method {
        values = condition.value["http_request_method"]
      }
    }
  }

  # Query string condition
  dynamic "condition" {
    for_each = [
      for condition_rule in var.listener_rules[count.index].conditions :
      condition_rule
      if length(lookup(condition_rule, "query_string", [])) > 0
    ]

    content {
      dynamic "query_string" {
        for_each = condition.value["query_string"]

        content {
          key   = lookup(query_string.value, "key", null)
          value = query_string.value["value"]
        }
      }
    }
  }

  # Source IP address condition
  dynamic "condition" {
    for_each = [
      for condition_rule in var.listener_rules[count.index].conditions :
      condition_rule
      if length(lookup(condition_rule, "source_ip", [])) > 0
    ]

    content {
      source_ip {
        values = condition.value["source_ip"]
      }
    }
  }

  tags = merge(local.tags, var.listener_rules[count.index].tags)
}
