output "alb_name" {
  description = "The ARN suffix of the ALB"
  value       = aws_lb.this.name
}

output "alb_arn" {
  description = "The ARN of the ALB"
  value       = aws_lb.this.arn
}

output "alb_dns_name" {
  description = "DNS name of ALB"
  value       = aws_lb.this.dns_name
}

output "alb_zone_id" {
  description = "The ID of the zone which ALB is provisioned"
  value       = aws_lb.this.zone_id
}

output "target_group_arns" {
  description = "A list of all the target group ARNs"
  value       = values(aws_lb_target_group.this)[*].arn
}

output "target_group_names" {
  description = "A list of all the target group names"
  value       = values(aws_lb_target_group.this)[*].name
}

output "listener_arns" {
  description = "A list of all the listener ARNs"
  value       = values(aws_lb_listener.this)[*].arn
}
