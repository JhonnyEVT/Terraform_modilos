check "no_logging_warning" {
  assert {
    condition     = var.access_log_bucket_id != null
    error_message = <<EOF
Warning: Logging not enabled.  (Wiz VPC-040)
Access logs contain information such as the time the request was received, the client IP address, latencies, request paths, and server response data. The access logs can be used to analyze traffic patterns and troubleshoot issues. The logs are stored in an S3 bucket as compressed files.
EOF
  }
}

check "no_acm_certificate_warning" {
  assert {
    condition = !anytrue([
      for listener in var.listeners :
      listener.protocol == "HTTPS" &&
      listener.certificate_arn == null
    ])
    error_message = <<EOF
Warning: No ACM Certificate Defined.  (Wiz ELB-056)
It is recommended to use ACM certificates for Application and Network Load Balancer listeners to ensure proper certificate management and enhanced security for your load balancer's HTTPS connections.
EOF
  }
}

check "no_tls_warning" {
  assert {
    condition = !anytrue([
      for listener in var.listeners :
      listener.protocol != "HTTPS" && # If it's not HTTPS and there is no redirect
      listener.redirect == null
    ])
    error_message = <<EOF
Warning: Listener not using HTTPS (Wiz ELB-047)
HTTPS is not enabled, or HTTP is being allowed without redirect.  This could result in un-encrypted communication.  Make sure this is your intention.
EOF
  }
}

check "tls_less_than_12_warning" {
  assert {
    condition = anytrue([
      for listener in var.listeners :
      (listener.protocol == "HTTPS" && try(
        strcontains(listener.ssl_policy, "TLS13-1-3") ||
        strcontains(listener.ssl_policy, "TLS13-1-2") ||
      strcontains(listener.ssl_policy, "TLS-1-2"), false)) ||
      try(listener.default_action.type == "forward", false)
    ])
    error_message = <<EOF
Warning: Application Load Balancer should use TLS version 1.2 or higher  (Wiz ELB-010)
Outdated TLS protocols are considered insecure as they might be vulnerable to man-in-the-middle exploits, allowing an attacker to decrypt and access encrypted data. Ensure the ALB supports TLSv1.2 or higher.
EOF
  }
}

check "no_healthcheck_warning" {
  assert {
    condition = !anytrue([
      for target in var.target_groups :
      target.health_check == null
    ])
    error_message = <<EOF
Warning: Application Load balancer Target group Healthcheck should be defined (Wiz ELB-051)
Target Groups are used to route requests to one or more registered targets. Health checks are crucial for ensuring that traffic is only routed to healthy instances. Without a properly configured health check, the load balancer might send requests to unhealthy instances, potentially causing service disruptions or failures.
It is recommended to define a health check with a specific path for HTTP/HTTPS Target Groups to maintain service reliability and availability.
EOF
  }
}