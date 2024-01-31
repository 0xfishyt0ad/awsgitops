####################################################################################################
### Define common variables
####################################################################################################
locals {
  name = "env-${var.facts.environment}-apigateway-${var.name}"
}

####################################################################################################
### Create API Gateway
####################################################################################################
resource "aws_apigatewayv2_api" "this" {
  name                         = "${local.name}-api"
  protocol_type                = "HTTP"
  api_key_selection_expression = "$request.header.x-api-key"
  route_selection_expression   = "$request.method $request.path"

  tags = var.facts
}

####################################################################################################
### Get data about LB listener and create API integration
####################################################################################################
data "aws_lb" "this" {
  name = var.lb_name
}

data "aws_lb_listener" "this" {
  load_balancer_arn = data.aws_lb.this.arn
  port              = 80
}

resource "aws_apigatewayv2_integration" "this" {
  api_id             = aws_apigatewayv2_api.this.id
  connection_id      = var.vpc_link_id
  connection_type    = "VPC_LINK"
  integration_method = "ANY"
  integration_type   = "HTTP_PROXY"
  integration_uri    = data.aws_lb_listener.this.arn
}

####################################################################################################
### Create route and stage
####################################################################################################
resource "aws_apigatewayv2_route" "this" {
  api_id    = aws_apigatewayv2_api.this.id
  route_key = "$default"
  target    = "integrations/${aws_apigatewayv2_integration.this.id}"
}

resource "aws_apigatewayv2_stage" "this" {
  api_id      = aws_apigatewayv2_api.this.id
  name        = "$default"
  auto_deploy = "true"

  tags = var.facts
}

####################################################################################################
### Create API domain, DNS record and glue everything together
####################################################################################################
resource "aws_apigatewayv2_domain_name" "this" {
  domain_name = "${var.name}.${var.domain}"

  domain_name_configuration {
    certificate_arn = var.certificate_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }

  tags = var.facts
}

resource "aws_route53_record" "this" {
  name    = aws_apigatewayv2_domain_name.this.domain_name
  records = [aws_apigatewayv2_domain_name.this.domain_name_configuration.0.target_domain_name]
  ttl     = 60
  type    = "CNAME"
  zone_id = var.zone_id
}

resource "aws_apigatewayv2_api_mapping" "this" {
  api_id      = aws_apigatewayv2_api.this.id
  domain_name = aws_apigatewayv2_domain_name.this.id
  stage       = aws_apigatewayv2_stage.this.id
}