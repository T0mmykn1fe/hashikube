# https://www.terraform.io/docs/providers/google/r/compute_instance.html
# https://github.com/terraform-providers/terraform-provider-google/blob/master/examples/internal-load-balancing/main.tf

provider "google" {
  credentials = file("~/.gcp/credentials.json")
  project     = var.gcp_project
  region      = var.gcp_region
}

resource "google_compute_region_instance_group_manager" "hashikube" {
  name     = "hashikube"
  provider = google

  base_instance_name        = var.gcp_cluster_name
  region                    = var.gcp_region
  distribution_policy_zones = var.gcp_zones

  version {
    name              = var.gcp_cluster_name
    instance_template = google_compute_instance_template.hashikube.self_link
  }

  target_size = var.gcp_cluster_size

  depends_on = [google_compute_instance_template.hashikube]

  update_policy {
    type           = "PROACTIVE"
    minimal_action = "REPLACE"

    max_surge_fixed       = 3
    max_unavailable_fixed = 0
    min_ready_sec         = 60
  }
}

data "google_compute_subnetwork" "default" {
  provider = google
  name     = "default"
}

resource "google_compute_instance_template" "hashikube" {
  provider    = google
  name_prefix = var.gcp_cluster_name
  description = var.gcp_cluster_description

  instance_description = var.gcp_cluster_description
  machine_type         = var.gcp_machine_type

  tags = list(var.gcp_cluster_tag_name)

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = false
  }

  disk {
    boot         = true
    auto_delete  = true
    source_image = "ubuntu-os-cloud/ubuntu-1804-lts"
    disk_size_gb = var.gcp_root_volume_disk_size_gb
    disk_type    = var.gcp_root_volume_disk_type
  }

  metadata_startup_script = file("./startup_script")
  metadata = {
    ssh-keys = "ubuntu:${file("~/.ssh/id_rsa.pub")}"
  }

  network_interface {
    subnetwork = data.google_compute_subnetwork.default.self_link

    access_config {
      nat_ip = google_compute_address.static.address
    }
  }

  service_account {
    email  = google_service_account.consul_compute.email
    scopes = ["userinfo-email", "compute-ro", "storage-rw"]
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "google_compute_address" "static" {
  name = "hashikube"
}

resource "google_compute_firewall" "allow_intercluster_consul_inbound" {
  name    = "${var.gcp_cluster_name}-rule-consul-inter-inbound"
  network = "default"
  project = var.gcp_project

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  source_ranges           = ["${data.external.myipaddress.result.ip}/32", "${aws_eip.hashikube.public_ip}/32"]
  source_service_accounts = [google_service_account.consul_compute.email]
  target_service_accounts = [google_service_account.consul_compute.email]
}

resource "google_compute_firewall" "allow_cluster_consul_wan" {
  name    = "${var.gcp_cluster_name}-rule-consul-wan"
  network = "default"
  project = var.gcp_project

  allow {
    protocol = "tcp"
    ports    = ["0-65535"]
  }

  allow {
    protocol = "udp"
    ports    = ["0-65535"]
  }

  source_ranges           = ["${data.external.myipaddress.result.ip}/32", "${aws_eip.hashikube.public_ip}/32"]
  target_service_accounts = [google_service_account.consul_compute.email]
}

resource "google_service_account" "consul_compute" {
  account_id   = "sa-consul-compute-prod"
  display_name = "Consul Primary Account for ${var.gcp_project}"
  project      = var.gcp_project
}

resource "google_project_iam_member" "compute_policy" {
  project = var.gcp_project
  role    = "roles/compute.networkViewer"
  member  = "serviceAccount:${google_service_account.consul_compute.email}"
}

output "GCP_hashikube2-service-consul" {
  value = google_compute_address.static.address
}

output "GCP_hashikube2-ssh-service-consul" {
  value = "ssh ubuntu@${google_compute_address.static.address}"
}

output "GCP_hashikube2-consul-service-consul" {
  value = "http://${google_compute_address.static.address}:8500"
}

output "GCP_hashikube2-nomad-service-consul" {
  value = "http://${google_compute_address.static.address}:4646"
}

output "GCP_hashikube2-fabio-ui-service-consul" {
  value = "http://${google_compute_address.static.address}:9998"
}
