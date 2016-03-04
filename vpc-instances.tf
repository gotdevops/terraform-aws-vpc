
############################
# NAT Instance
############################

resource "aws_instance" "nat" {
	instance_type = "${var.nat_instance_type}"
	ami = "${lookup(var.nat_amis, var.aws_region)}"
	key_name = "${var.aws_keypair_name}"

	# required for nat - source_dest_check = false
	source_dest_check = false
	associate_public_ip_address = true

	subnet_id = "${aws_subnet.dmz.id}"
	private_ip = "${var.vpc_cidr_prefix}.0.250"

	vpc_security_group_ids = ["${aws_security_group.nat.id}"]

	root_block_device {
		delete_on_termination = true
	}

	tags {
		Name ="nat-${var.site_environment}"
		Environment = "${var.site_environment}"

        FullRole = "${var.site_environment}-nat"
		Role = "nat"
	}

	provisioner "local-exec" {
		command = "${path.module}/ansible/install-requirements.sh"
	}

	# wait until jump server is up
	provisioner "local-exec" {
		command = "sleep ${var.sleep_seconds * 3}" #it takes a while for the NAT server to come up
	}

	# create tunnel 
	provisioner "local-exec" {
		command = "ssh -i ${var.aws_private_key} -f -L 12986:${self.private_ip}:22 ubuntu@${aws_eip.jump.public_ip} -o StrictHostKeyChecking=no sleep ${var.ssh_wait_seconds} <&- >&- 2>&- &"
	}

	connection {
		type = "ssh"
		user = "ec2-user"
		private_key = "${var.aws_private_key}"
		agent = false
		port = 12986
		host = "127.0.0.1"
	}

	#this is here because it is more resilent for the initial connect
	provisioner "remote-exec" {
		inline = [
			"echo connected"
		]
	}

	provisioner "local-exec" {
		command = "${path.module}/ansible/nat/run-play ${var.aws_private_key}"
	}

	provisioner "remote-exec" {
		inline = [
			"sudo yum update -y"
		]
	}
}

resource "aws_instance" "provision" {
	depends_on = ["aws_route_table.nat", "aws_instance.nat"]
	instance_type = "${var.provision_instance_type}"
	ami = "${lookup(var.ubuntu_amis, var.aws_region)}"
	key_name = "${var.aws_keypair_name}"

	subnet_id = "${aws_subnet.provision.id}"
	private_ip = "${var.vpc_cidr_prefix}.96.7"

	vpc_security_group_ids = [
		"${aws_security_group.ssh_base.id}", 
		"${aws_security_group.provision.id}"
	]
	
	root_block_device {
		delete_on_termination = true
	}

	tags {
		Name ="provision-${var.site_environment}"
		Environment = "${var.site_environment}"

		FullRole = "${var.site_environment}-provision"
		Role = "provision"
	}

	provisioner "local-exec" {
		command = "${path.module}/ansible/install-requirements.sh"
	}

	# wait until jump server is up
	provisioner "local-exec" {
		command = "sleep ${var.sleep_seconds}" #it takes a little while for the server to come up
	}

	provisioner "local-exec" {
		command = "ssh -i ${var.aws_private_key} -f -L 12987:${self.private_ip}:22 ubuntu@${aws_eip.jump.public_ip} -o StrictHostKeyChecking=no sleep ${var.ssh_wait_seconds} <&- >&- 2>&- &"
	}

	connection {
		type = "ssh"
		user = "ubuntu"
		private_key = "${var.aws_private_key}"
		agent = false
		port = 12987
		host = "127.0.0.1"
	}

	#this is here because it is more resilent than file for the initial connect
	provisioner "remote-exec" {
		inline = [
			"echo connected"
		]
	}

	provisioner "file" {
		source = "${var.aws_private_key}"
		destination = "~/.ssh/current"
    }

	provisioner "remote-exec" {
		inline = [
			"chmod 600 ~/.ssh/current",
		]
	}

	provisioner "local-exec" {
		command = "${path.module}/ansible/provision/run-play ${var.aws_private_key}"
	}
}

resource "aws_instance" "jump" {
	depends_on = ["aws_internet_gateway.main"]
	instance_type = "${var.jump_instance_type}"
	ami = "${lookup(var.jump_amis, var.aws_region)}"
	key_name = "${var.aws_keypair_name}" 

	associate_public_ip_address = true

	subnet_id = "${aws_subnet.dmz.id}"
	private_ip = "${var.vpc_cidr_prefix}.0.7"

	vpc_security_group_ids = ["${aws_security_group.jump.id}"]

	root_block_device {
		delete_on_termination = true
	}
	tags {
		Name ="jump-${var.site_environment}"
		Environment = "${var.site_environment}"

		FullRole = "${var.site_environment}-jump"
		Role = "jump"
	}

	connection {
		type = "ssh"
		user = "ubuntu"
		private_key = "${var.aws_private_key}"
	}

	provisioner "local-exec" {
		command = "${path.module}/ansible/install-requirements.sh"
	}

	provisioner "local-exec" {
		command = "sleep ${var.sleep_seconds}" #it takes a little while for the server to come up
	}

	#this is here because it is more resilent than file for the initial connect
	provisioner "remote-exec" {
		inline = [
			"echo connected"
		]
	}

	provisioner "file" {
		source = "${var.aws_private_key}"
		destination = "~/.ssh/current"
    }

	provisioner "remote-exec" {
		inline = [
			"chmod 600 ~/.ssh/current"
		]
	}

	provisioner "local-exec" {
		command = "echo '${self.public_ip}' > ${path.module}/ansible/jump/inventory.ini"
	}

	provisioner "local-exec" {
		command = "${path.module}/ansible/jump/run-play ${var.aws_private_key}"
	}

	provisioner "remote-exec" {
		inline = [
			"echo connected"
		]
	}

	provisioner "remote-exec" {
		inline = [
			"sudo apt-get update"
		]
	}
}


