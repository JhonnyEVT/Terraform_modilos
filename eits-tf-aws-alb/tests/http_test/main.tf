# test region
provider "aws" {
  region = var.region
}

# create ec2 to use for testing load balancer
module "test_ec2" {
  source = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-ec2-innersource.git"

  ec2_name         = "eits-tf-aws-alb-http"
  ami              = "amzn_lnx_2023"
  instance_type    = "t3.micro"
  vpc_id           = var.vpc_id
  subnet           = var.subnet_ids[0]
  root_volume_type = "gp3"
  root_volume_size = "50"

  security_group_name        = "eits-tf-aws-alb-http"
  security_group_description = "eits-tf-aws-alb-http"

  security_group_ingress_rules = [
    {
      description = "ssh"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = ["10.0.0.0/8"]
    }
  ]
  security_group_egress_rules = [
    {
      type        = "egress"
      from_port   = "0"
      to_port     = "0"
      protocol    = "-1"
      cidr_blocks = ["10.0.0.0/8"]
      description = "Allow outbound traffic to Experian network"
    }
  ]

  disable_default_alarms = true

  tags = var.tags
}

# test module
# Ignoring Trivy error for using HTTP protocol as this is desired for the test
#tfsec:ignore:AVD-AWS-0054
module "alb" {
  source = "./../.."

  alb_name   = "eits-tf-aws-alb-http"
  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  security_groups = [module.test_ec2.security_group_id]

  enable_deletion_protection = false

  target_groups = {
    eits-tf-aws-alb = {
      port     = 80
      protocol = "HTTP"
      health_check = {
        enabled = true
        port    = "traffic-port"
      }
      target_type = "instance"
      targets = [
        {
          name      = "eits-tf-aws-alb"
          target_id = module.test_ec2.id
        }
      ]
    }
  }

  listeners = [
    {
      port                 = 80
      protocol             = "HTTP"
      default_target_group = "eits-tf-aws-alb"
    }
  ]

  listener_rules = [
    {
      listener         = "http_80"
      target_group_key = "eits-tf-aws-alb"
      priority         = 1
      actions = [
        {
          type = "forward"
          target_groups = [
            {
              target_group_key = "eits-tf-aws-alb"
              weight           = 1
            }
          ]
          stickiness = {
            enabled  = true
            duration = 3600
          }
        }
      ]
      conditions = [
        {
          query_string = [
            {
              key   = "weighted"
              value = "true"
            }
          ]
        }
      ]
    }
  ]
  tags = var.tags
}
