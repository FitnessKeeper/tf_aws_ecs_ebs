locals {
  data_device = "/dev/xvdcv"
  second_asg_instance_type = coalesce(var.second_asg_instance_type, var.instance_type)
}

data "aws_ami" "ecs_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-${var.ami_version}-x86_64-ebs"]
  }
}

data "aws_ebs_snapshot" "data" {
  most_recent = "true"
  owners      = ["self"]

  filter {
    name   = "tag:Name"
    values = [var.ebs_snapshot_matcher]
  }
}

data "template_file" "user_data" {
  template = file("${path.module}/templates/user_data.tpl")

  vars = {
    additional_user_data_script = var.additional_user_data_script
    cluster_name                = aws_ecs_cluster.cluster.name
    docker_storage_size         = var.docker_storage_size
    dockerhub_token             = var.dockerhub_token
    dockerhub_email             = var.dockerhub_email
    data_device                 = local.data_device
    region                      = var.region
    eni_trunking_desired_setting = var.blue_eni_trunking_enabled == null ? "unset" : var.blue_eni_trunking_enabled
  }
}

data "template_file" "user_data_al1" { # Amazon Linux 1 Blue Cluster
  template = file("${path.module}/templates/user_data_al1.tpl")

  vars = {
    additional_user_data_script = var.additional_user_data_script_al1
    cluster_name                = aws_ecs_cluster.cluster.name
    docker_storage_size         = var.docker_storage_size
    dockerhub_token             = var.dockerhub_token
    dockerhub_email             = var.dockerhub_email
    region                      = var.region
    data_device                 = local.data_device
    eni_trunking_desired_setting = var.blue_eni_trunking_enabled == null ? "unset" : var.blue_eni_trunking_enabled
  }
}

data "template_file" "user_data_second" {
  template = file("${path.module}/templates/user_data.tpl")

  vars = {
    additional_user_data_script = var.additional_user_data_script
    cluster_name                = aws_ecs_cluster.cluster.name
    docker_storage_size         = var.docker_storage_size
    dockerhub_token             = var.dockerhub_token
    dockerhub_email             = var.dockerhub_email
    region                      = var.region
    data_device                 = local.data_device
    eni_trunking_desired_setting = var.green_eni_trunking_enabled == null ? "unset" : var.green_eni_trunking_enabled
  }
}

data "template_file" "user_data_second_al1" { # Amazon Linux 1 Green Cluster
  template = file("${path.module}/templates/user_data_al1.tpl")

  vars = {
    additional_user_data_script = var.additional_user_data_script_al1
    cluster_name                = aws_ecs_cluster.cluster.name
    docker_storage_size         = var.docker_storage_size
    dockerhub_token             = var.dockerhub_token
    dockerhub_email             = var.dockerhub_email
    region                      = var.region
    data_device                 = local.data_device
    eni_trunking_desired_setting = var.green_eni_trunking_enabled == null ? "unset" : var.green_eni_trunking_enabled
  }
}

resource "aws_ssm_parameter" "eni_trunking_mismatch_on_boot_terminate_instance" {
  name  = "/ecs-cluster/${var.name}/eni_trunking_mismatch_on_boot_terminate_instance"
  type  = "String"
  value = var.eni_trunking_mismatch_on_boot_terminate_instance == null ? "unset" : var.eni_trunking_mismatch_on_boot_terminate_instance
}

data "aws_vpc" "vpc" {
  id = var.vpc_id
}

resource "aws_launch_configuration" "ecs" {
  name_prefix          = coalesce(var.name_prefix, "ecs-${var.name}-")
  image_id             = var.ami == "" ? format("%s", data.aws_ami.ecs_ami.id) : var.ami # Workaround until 0.9.6
  instance_type        = var.instance_type
  key_name             = var.key_name
  iam_instance_profile = aws_iam_instance_profile.ecs_profile.name
  # TF-UPGRADE-TODO: In Terraform v0.10 and earlier, it was sometimes necessary to
  # force an interpolation expression to be interpreted as a list by wrapping it
  # in an extra set of list brackets. That form was supported for compatibility in
  # v0.11, but is no longer supported in Terraform v0.12.
  #
  # If the expression in the following list itself returns a list, remove the
  # brackets to avoid interpretation as a list of lists. If the expression
  # returns a single list item then leave it as-is and remove this TODO comment.
  security_groups             = concat(list(aws_security_group.ecs.id), var.security_group_ids)
  associate_public_ip_address = var.associate_public_ip_address
  spot_price                  = var.spot_bid_price

  ebs_block_device {
    device_name           = var.ebs_block_device
    volume_size           = var.docker_storage_size
    volume_type           = "gp2"
    delete_on_termination = true
  }

  ebs_block_device {
    snapshot_id           = data.aws_ebs_snapshot.data.id
    device_name           = local.data_device
    volume_type           = "gp2"
    delete_on_termination = true
  }

  user_data = coalesce(var.user_data, var.blue_al1 ? data.template_file.user_data_al1.rendered : data.template_file.user_data.rendered)

  lifecycle {
    create_before_destroy = true
  }
}

# Optional Second Launch Config for the optional Second ASG
resource "aws_launch_configuration" "ecs_second" {
  count                = var.second_asg_servers > 0 ? 1 : 0
  name_prefix          = coalesce(var.name_prefix, "ecs-second-${var.name}-")
  image_id             = var.second_asg_ami == "" ? format("%s", data.aws_ami.ecs_ami.id) : var.second_asg_ami # Workaround until 0.9.6
  instance_type        = local.second_asg_instance_type
  key_name             = var.key_name
  iam_instance_profile = aws_iam_instance_profile.ecs_profile.name
  # TF-UPGRADE-TODO: In Terraform v0.10 and earlier, it was sometimes necessary to
  # force an interpolation expression to be interpreted as a list by wrapping it
  # in an extra set of list brackets. That form was supported for compatibility in
  # v0.11, but is no longer supported in Terraform v0.12.
  #
  # If the expression in the following list itself returns a list, remove the
  # brackets to avoid interpretation as a list of lists. If the expression
  # returns a single list item then leave it as-is and remove this TODO comment.
  security_groups             = concat(list(aws_security_group.ecs.id), var.security_group_ids)
  associate_public_ip_address = var.associate_public_ip_address
  spot_price                  = var.spot_bid_price

  ebs_block_device {
    device_name           = var.ebs_block_device
    volume_size           = var.docker_storage_size
    volume_type           = "gp2"
    delete_on_termination = true
  }

  ebs_block_device {
    snapshot_id           = data.aws_ebs_snapshot.data.id
    device_name           = local.data_device
    volume_type           = "gp2"
    delete_on_termination = true
  }

  user_data = coalesce(var.user_data, var.green_al1 ? data.template_file.user_data_second_al1.rendered : data.template_file.user_data_second.rendered)

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    "aws_ssm_parameter.eni_trunking_mismatch_on_boot_terminate_instance"
  ]
}

resource "aws_autoscaling_group" "ecs" {
  name_prefix          = "asg-${aws_launch_configuration.ecs.name}-"
  vpc_zone_identifier  = var.subnet_id
  launch_configuration = aws_launch_configuration.ecs.name
  min_size             = var.min_servers
  max_size             = var.max_servers
  desired_capacity     = var.servers
  termination_policies = ["OldestLaunchConfiguration", "ClosestToNextInstanceHour", "Default"]

  tags = concat([
   {
    key                 = "Name"
    value               = "${var.name} ${var.tagName}"
    propagate_at_launch = true
  }], var.extra_tags)

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "ecs" {
  name        = "ecs-sg-${var.name}"
  description = "Container Instance Allowed Ports"
  vpc_id      = data.aws_vpc.vpc.id

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = var.allowed_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "ecs-sg-${var.name}"
  }
}

# Make this a var that an get passed in?
resource "aws_ecs_cluster" "cluster" {
  name = var.name
}
