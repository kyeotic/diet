#Variable for this file, used to determine when apig changes are made to redeploy the api gateway stage
variable "apiGatewayTerraformFile" {
  default = "./api.tf"
}

#API Gateway config
resource "aws_api_gateway_rest_api" "api" {
  name               = "${local.api_gateway_name}"
  binary_media_types = ["application/octet-stream"]

  # endpoint_configuration {
  #   types = ["REGIONAL"]
  # }
}

# V1 root
resource "aws_api_gateway_resource" "get_resource_v1" {
  rest_api_id = "${aws_api_gateway_rest_api.api.id}"
  parent_id   = "${aws_api_gateway_rest_api.api.root_resource_id}"
  path_part   = "v1"
}

##
# Greedy path proxy
##
resource "aws_api_gateway_resource" "proxy_resource" {
  rest_api_id = "${aws_api_gateway_rest_api.api.id}"
  parent_id   = "${aws_api_gateway_resource.get_resource_v1.id}"
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy_all_methods" {
  rest_api_id   = "${aws_api_gateway_rest_api.api.id}"
  resource_id   = "${aws_api_gateway_resource.proxy_resource.id}"
  http_method   = "ANY"
  authorization = "NONE"
  # authorizer_id = "${aws_api_gateway_authorizer.node_authorizer.id}"
}

resource "aws_api_gateway_integration" "proxy_all_integration" {
  rest_api_id             = "${aws_api_gateway_rest_api.api.id}"
  resource_id             = "${aws_api_gateway_resource.proxy_resource.id}"
  http_method             = "${aws_api_gateway_method.proxy_all_methods.http_method}"
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = "${aws_lambda_function.api.invoke_arn}"
}

# options
module "api_gateway_cors_proxy" {
  source          = "github.com/squidfunk/terraform-aws-api-gateway-enable-cors"
  version         = "0.2.0"
  api_id          = "${aws_api_gateway_rest_api.api.id}"
  api_resource_id = "${aws_api_gateway_resource.proxy_resource.id}"
}

#Permission to execute lambda from api gateway event
resource "aws_lambda_permission" "apig_lambda" {
  action        = "lambda:InvokeFunction"
  function_name = "${aws_lambda_function.api.arn}"
  principal     = "apigateway.amazonaws.com"
  statement_id  = "AllowExecutionFromAPIGateway"
  source_arn    = "${aws_api_gateway_rest_api.api.execution_arn}/*/*/*"
}

#Stage definition
resource "aws_api_gateway_deployment" "apig_deployment" {
  depends_on = [
    "aws_api_gateway_integration.proxy_all_integration",
  ]

  rest_api_id       = "${aws_api_gateway_rest_api.api.id}"
  stage_name        = "${local.api_stage}"
  # This is important, it will cause the stage to get deployed if this file is changed.
  # If it is not present the stage will not get updated even on dependent apig resource changes.
  stage_description = "${base64sha256(file(var.apiGatewayTerraformFile))}"

  variables {
    "stage" = "${local.api_stage}"
    "depends" = "${aws_api_gateway_integration.proxy_all_integration.id}"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# resource "aws_api_gateway_method_settings" "s" {
#   rest_api_id = "${aws_api_gateway_rest_api.api.id}"
#   stage_name  = "${aws_api_gateway_deployment.apig_deployment.stage_name}"
#   method_path = "*/*"

#   settings {
#     metrics_enabled = true
#     logging_level = "INFO"
#   }
# }

resource "aws_api_gateway_base_path_mapping" "api" {
  depends_on = [
    "aws_api_gateway_deployment.apig_deployment",
  ]

  api_id      = "${aws_api_gateway_rest_api.api.id}"
  domain_name = "${aws_api_gateway_domain_name.api_domain.domain_name}"
  stage_name  = "${aws_api_gateway_deployment.apig_deployment.stage_name}"
  base_path   = ""
}

#Display the invoke url in the terminal
output "display_invoke_url" {
  value = "Invoke URL: ${aws_api_gateway_deployment.apig_deployment.invoke_url}"
}
