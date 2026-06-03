variable "subnet_ids" {
  type        = list(string)
  description = "A list of subnet IDs to associate with ALB"
  default     = ["subnet-0007176f4041512f4", "subnet-07f7f119f8527be21"]
}

variable "tags" {
  type        = map(string)
  description = "Tags for AWS resources. See [Cloud Tagging Strategy & Standards](https://pages.experian.com/pages/viewpage.action?pageId=400041906) for available tags"
  default     = {}
}

variable "vpc_id" {
  type        = string
  description = "VPC ID to associate with ALB"
  default     = "vpc-044f838833610a3f6"
}

variable "region" {
  type        = string
  description = "AWS region to provision into"
  default     = "eu-west-2"
}
