data "template_file" "consul" {
  template = file("${path.module}/templates/consul.json")

  vars = {
    env                   = aws_ecs_cluster.cluster.name
    image                 = var.consul_image
    registrator_image     = var.registrator_image
    awslogs_group         = "consul-agent-${aws_ecs_cluster.cluster.name}"
    awslogs_stream_prefix = "consul-agent-${aws_ecs_cluster.cluster.name}"
    awslogs_region        = var.region
  }
}

# End Data block

resource "aws_ecs_task_definition" "consul" {
  count                 = var.enable_agents ? 1 : 0
  family                = "consul-agent-${aws_ecs_cluster.cluster.name}"
  container_definitions = data.template_file.consul.rendered
  network_mode          = "host"
  task_role_arn         = aws_iam_role.consul_task[0].arn

  volume {
    name      = "consul-config-dir"
    host_path = "/etc/consul"
  }

  volume {
    name      = "docker-sock"
    host_path = "/var/run/docker.sock"
  }
}

resource "aws_cloudwatch_log_group" "consul" {
  count = var.enable_agents ? 1 : 0
  name  = aws_ecs_task_definition.consul[0].family

  tags = {
    VPC         = data.aws_vpc.vpc.tags["Name"]
    Application = aws_ecs_task_definition.consul[0].family
  }
}

resource "aws_ecs_service" "consul" {
  count           = var.enable_agents ? 1 : 0
  name            = "consul-agent-${aws_ecs_cluster.cluster.name}"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.consul[0].arn
  desired_count   = var.servers

  placement_constraints {
    type = "distinctInstance"
  }
}

