####################################################################################################
### Create CNAME DNS record for LB by name prefix
####################################################################################################
data "aws_lb" "this" {
  name = var.lb_name
}

resource "aws_route53_record" "this" {
  name    = var.hostname
  records = [data.aws_lb.this.dns_name]
  ttl     = 60
  type    = "CNAME"
  zone_id = var.zone_id
}