# test region
provider "aws" {
  region = var.region
}

# create ec2 to use for testing load balancer
module "test_ec2" {
  source = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-ec2-innersource.git"

  ec2_name         = "eits-tf-aws-alb-https"
  ami              = "amzn_lnx_2023"
  instance_type    = "t3.micro"
  vpc_id           = var.vpc_id
  subnet           = var.subnet_ids[0]
  root_volume_type = "gp3"
  root_volume_size = "50"

  security_group_name        = "eits-tf-aws-alb-https"
  security_group_description = "eits-tf-aws-alb-https"

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

# create quick temporary certificate to use for testing plan
# DO NOT DO THIS FOR ACTUAL USECASES!
resource "tls_private_key" "this" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "tls_self_signed_cert" "this" {
  private_key_pem       = tls_private_key.this.private_key_pem
  ip_addresses          = [module.test_ec2.private_ip]
  validity_period_hours = 1
  allowed_uses = [
    "key_encipherment",
    "digital_signature",
    "client_auth",
  ]
}

module "acm" {
  source = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-acm.git"

  import_certificate = {
    private_key      = tls_private_key.this.private_key_pem
    certificate_body = tls_self_signed_cert.this.cert_pem
  }

  tags = var.tags
}

# duplicate cert just so we can test additional_certs key
module "acm_2" {
  source = "git::https://code.experian.local/scm/EUCES/eits-tf-aws-acm.git"

  import_certificate = {
    private_key      = tls_private_key.this.private_key_pem
    certificate_body = tls_self_signed_cert.this.cert_pem
  }

  tags = var.tags
}

# test module
module "alb" {
  source = "./../.."

  alb_name   = "eits-tf-aws-alb-https"
  vpc_id     = var.vpc_id
  subnet_ids = var.subnet_ids

  enable_deletion_protection = false

  target_groups = {
    eits-tf-aws-alb = {
      port     = 443
      protocol = "HTTPS"
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
      load_balancing_cross_zone_enabled = true
    }
  }

  listeners = [
    {
      port                 = 443
      protocol             = "HTTPS"
      default_target_group = "eits-tf-aws-alb"
      ssl_policy           = "ELBSecurityPolicy-TLS13-1-2-2021-06"
      certificate_arn      = module.acm.arn
      additional_certs     = [module.acm_2.arn]
    },
    {
      port     = 80
      protocol = "HTTP"
      redirect = {
        port        = "443"
        protocol    = "HTTPS"
        status_code = "HTTP_301"
      }
    }
  ]

  listener_rules = [
    {
      listener         = "https_443"
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
    },
    {
      listener         = "https_443"
      target_group_key = "eits-tf-aws-alb"
      priority         = 2
      actions = [
        {
          type = "forward"
        }
      ]
      transforms = [
        {
          type    = "url-rewrite"
          regex   = "/oldpath/(.*)"
          replace = "/newpath/$1"
        }
      ]
      conditions = [
        {
          path_pattern = ["/oldpath/*"]
        }
      ]
      tags = {
        Name = "example-rewrite"
      }
    }
  ]

  tags = var.tags
}
