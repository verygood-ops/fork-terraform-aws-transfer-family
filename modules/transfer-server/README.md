<!-- BEGIN_TF_DOCS -->
# AWS Transfer Family Terraform Module

This is a copy of the root module.

See the [main README](https://github.com/aws-ia/terraform-aws-transfer-family/blob/main/README.md) for complete documentation.

## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.95.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.95.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|
| [aws_cloudwatch_log_group.transfer](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [aws_route53_record.sftp](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/route53_record) | resource |
| [aws_transfer_server.transfer_server](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/transfer_server) | resource |
| [aws_transfer_tag.with_custom_domain_name](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/transfer_tag) | resource |
| [aws_transfer_tag.with_custom_domain_route53_zone_id](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/transfer_tag) | resource |
| [aws_route53_zone.selected](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone) | data source |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_custom_hostname"></a> [custom\_hostname](#input\_custom\_hostname) | The custom hostname for the Transfer Family server | `string` | `null` | no |
| <a name="input_dns_provider"></a> [dns\_provider](#input\_dns\_provider) | The DNS provider for the custom hostname. Use 'none' for no custom hostname | `string` | `null` | no |
| <a name="input_domain"></a> [domain](#input\_domain) | The domain of the storage system that is used for file transfers | `string` | `"S3"` | no |
| <a name="input_enable_logging"></a> [enable\_logging](#input\_enable\_logging) | Enable CloudWatch logging for the transfer server | `bool` | `false` | no |
| <a name="input_endpoint_details"></a> [endpoint\_details](#input\_endpoint\_details) | VPC endpoint configuration block for the Transfer Server | <pre>object({<br/>    address_allocation_ids = optional(list(string))<br/>    security_group_ids     = list(string)<br/>    subnet_ids             = list(string)<br/>    vpc_id                 = string<br/>  })</pre> | `null` | no |
| <a name="input_endpoint_type"></a> [endpoint\_type](#input\_endpoint\_type) | The type of endpoint that you want your transfer server to use | `string` | `"PUBLIC"` | no |
| <a name="input_identity_provider"></a> [identity\_provider](#input\_identity\_provider) | Identity provider configuration | `string` | `"SERVICE_MANAGED"` | no |
| <a name="input_log_group_kms_key_id"></a> [log\_group\_kms\_key\_id](#input\_log\_group\_kms\_key\_id) | encryption key for cloudwatch log group | `string` | `null` | no |
| <a name="input_log_retention_days"></a> [log\_retention\_days](#input\_log\_retention\_days) | Number of days to retain logs for | `number` | `30` | no |
| <a name="input_logging_role"></a> [logging\_role](#input\_logging\_role) | IAM role ARN that the Transfer Server assumes to write logs to CloudWatch Logs | `string` | `null` | no |
| <a name="input_protocols"></a> [protocols](#input\_protocols) | Specifies the file transfer protocol or protocols over which your file transfer protocol client can connect to your server's endpoint | `list(string)` | <pre>[<br/>  "SFTP"<br/>]</pre> | no |
| <a name="input_route53_hosted_zone_name"></a> [route53\_hosted\_zone\_name](#input\_route53\_hosted\_zone\_name) | The name of the Route53 hosted zone to use (must end with a period, e.g., 'example.com.') | `string` | `null` | no |
| <a name="input_security_policy_name"></a> [security\_policy\_name](#input\_security\_policy\_name) | Specifies the name of the security policy that is attached to the server. If not provided, the default security policy will be used. | `string` | `"TransferSecurityPolicy-2024-01"` | no |
| <a name="input_server_name"></a> [server\_name](#input\_server\_name) | The name of the Transfer Family server | `string` | `"transfer-server"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to assign to the resource | `map(string)` | `{}` | no |
| <a name="input_workflow_details"></a> [workflow\_details](#input\_workflow\_details) | Workflow details to attach to the transfer server | <pre>object({<br/>    on_upload = optional(object({<br/>      execution_role = string<br/>      workflow_id    = string<br/>    }))<br/>    on_partial_upload = optional(object({<br/>      execution_role = string<br/>      workflow_id    = string<br/>    }))<br/>  })</pre> | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_server_endpoint"></a> [server\_endpoint](#output\_server\_endpoint) | The endpoint of the created Transfer Family server |
| <a name="output_server_id"></a> [server\_id](#output\_server\_id) | The ID of the transfer server |
<!-- END_TF_DOCS -->