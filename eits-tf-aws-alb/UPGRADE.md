# Upgrade from v2 to v3 - 5th December 2023

## Added

- Argument `name` for `targets` argument. Due to the nature of the `for_each`, only **static** values are allowed for the `name` argument

## Modified

- Updated `aws_lb_target_group_attachment` resource to use `for_each` instead of `count`, so that the target group attachments are identifiable, and won't be recreated if any target group is added/removed/changed.

## Code upgrade

### BEFORE v3

```hcl
target_groups = {
    tg1 = {
      port     = 80
      protocol = "HTTP"
      health_check = {
        enabled = true
        port    = "traffic-port"
      }
      target_type = "instance"
      targets = [
        {
          target_id = module.ec2.id
        }
      ]
    }
  }
```

### v3 

```hcl
target_groups = {
    tg1 = {
      port     = 80
      protocol = "HTTP"
      health_check = {
        enabled = true
        port    = "traffic-port"
      }
      target_type = "instance"
      targets = [
        {
          name      = "tg1ec2"      # <-- A new arbitrary value is now required here
          target_id = module.ec2.id
        }
      ]
    }
  }
```
