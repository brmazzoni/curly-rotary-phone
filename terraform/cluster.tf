variable "do_token" {}

terraform {
    required_providers {
      digitalocean = {
          source = "digitalocean/digitalocean"
          version = "~> 2.0"
        }
    }
}

provider "digitalocean" {
    token = var.do_token
}

resource "digitalocean_kubernetes_cluster" "curly-rotary-cluster" {
    name = "curly-rotary-cluster"
    region = "sgp1"
    auto_upgrade = true
    version = "1.21.5-do.0"
    ha = true

    node_pool {
        name        = "node"
        size        = "s-2vcpu-2gb-amd"
        auto_scale  = true
        min_nodes   = 1
        max_nodes   = 11
    }
}

