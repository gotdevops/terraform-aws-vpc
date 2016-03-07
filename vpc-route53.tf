
resource "aws_route53_record" "jump" {
   zone_id = "${var.dns_jump_zone_id}"
   name = "jump.${var.dns_jump_domain}"

   type = "A"
   records = ["${aws_eip.jump.public_ip}"]
   ttl = "300"
}
