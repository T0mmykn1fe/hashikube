# https://www.terraform.io/docs/providers/aws/r/instance.html

provider "aws" {
  region                  = "ap-southeast-2"
  shared_credentials_file = "~/.aws/credentials"
  profile                 = "default"
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"] # Canonical
}

resource "aws_iam_role" "hashikube" {
  name = "hashikube"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF
}

resource "aws_iam_instance_profile" "hashikube" {
  name = "hashikube"
  role = aws_iam_role.hashikube.name
}

resource "aws_iam_role_policy" "hashikube" {
  name = "hashikube"
  role = aws_iam_role.hashikube.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "ec2:Describe*"
      ],
      "Effect": "Allow",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_instance" "hashikube" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t2.medium"

  security_groups = [aws_security_group.hashikube.name]

  key_name  = aws_key_pair.hashikube.key_name
  user_data = file("./startup_script")

  iam_instance_profile = aws_iam_instance_profile.hashikube.name

  tags = {
    Name = "hashikube"
  }
}

resource "aws_key_pair" "hashikube" {
  key_name   = "hashikube"
  public_key = file("~/.ssh/id_rsa.pub")
}

resource "aws_security_group" "hashikube" {
  name = "hashikube"

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["${data.external.myipaddress.result.ip}/32"]
  }

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "tcp"
    cidr_blocks = ["${google_compute_address.static.address}/32"]
    description = "HASHIQUBE2_IP"
  }

  ingress {
    from_port   = 0
    to_port     = 65535
    protocol    = "udp"
    cidr_blocks = ["${data.external.myipaddress.result.ip}/32", "${google_compute_address.static.address}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_eip_association" "eip_assoc" {
  instance_id   = aws_instance.hashikube.id
  allocation_id = aws_eip.hashikube.id
}

resource "aws_eip" "hashikube" {
  vpc = true
}

output "AWS_hashikube1-service-consul" {
  value = aws_eip.hashikube.public_ip
}

output "AWS_hashikube1-ssh-service-consul" {
  value = "ssh ubuntu@${aws_eip.hashikube.public_ip}"
}

output "AWS_hashikube1-consul-service-consul" {
  value = "http://${aws_eip.hashikube.public_ip}:8500"
}

output "AWS_hashikube1-nomad-service-consul" {
  value = "http://${aws_eip.hashikube.public_ip}:4646"
}

output "AWS_hashikube1-fabio-ui-service-consul" {
  value = "http://${aws_eip.hashikube.public_ip}:9998"
}
