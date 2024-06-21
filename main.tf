
#----------------------VPC + subnet for machine group------------------------------------------

resource "yandex_vpc_network" "vpc-main" {
  name = "main-vpc"
}

resource "yandex_vpc_subnet" "public-subnet" {
  name           = "public-subnet"
  v4_cidr_blocks = ["10.5.0.0/16"]
  zone           = "ru-central1-a"
  network_id     = yandex_vpc_network.vpc-main.id
}

#----------------------VPC + subnet for Pg cluster------------------------------------------

resource "yandex_vpc_network" "vpc-for-pg-cluster" {
  name = "vpc-for-pg-cluster"
}

resource "yandex_vpc_subnet" "subnet-for-pg-cluster" {
  name           = "pg-subnet"
  v4_cidr_blocks = ["10.6.0.0/24"]
  zone           = "ru-central1-b"
  network_id     = yandex_vpc_network.vpc-for-pg-cluster.id
}

#-------------------------------------Security Group for group1--------------------------------------------------------------------

resource "yandex_vpc_security_group" "vm-sg" {
  name       = "security-group-for-vm"
  network_id = yandex_vpc_network.vpc-main.id

  egress {
    protocol       = "ANY"
    description    = "Allow all egress traffic"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }

  ingress {
    description    = "HTTP"
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 80
  }

  ingress {
    description    = "HTTPS"
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 443
  }

  ingress {
    description    = "SSH"
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
    port           = 22
  }
}

#-----------------------------------------Security group for postgresql cluster-----------------------------------------

resource "yandex_vpc_security_group" "pgsql-sg" {
  name       = "pgsql-sg"
  network_id = yandex_vpc_network.vpc-for-pg-cluster.id

  ingress {
    description    = "PostgreSQL"
    port           = 6432
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}


#----------------------Virtual Machines (Group machines)-----------------------------------------------------------


resource "yandex_compute_instance_group" "group1" {
  name                = "group-application"
  folder_id           = var.yc_folder_id
  service_account_id  = var.yc_service_account_id
  deletion_protection = false

  instance_template {
    platform_id = "standard-v1"
    resources {
      memory = 2
      cores  = 2
    }
    boot_disk {
      mode = "READ_WRITE"
      initialize_params {
        image_id = var.centos_image_id
        size     = 20
      }
    }
    network_interface {
      network_id         = yandex_vpc_network.vpc-main.id
      subnet_ids         = ["${yandex_vpc_subnet.public-subnet.id}"]
      security_group_ids = [yandex_vpc_security_group.vm-sg.id]
      nat                = true
      #       ip_address = "{ip_{instance.tag}}"
      #       nat_ip_address = "{external_ip_{instance.tag}}"
    }
    labels = {
      label1 = "label1-value"
    }
    metadata = {
      foo      = "bar"
      ssh-keys = "ubuntu:${file("/etc/ssh/id_rsa.pub")}"
    }

    network_settings {
      type = "STANDARD"
    }
  }

  variables = {
    # --------------------------Below block for static ip address for each server in server group----------------
    #     ip_ru1-a1 = "192.168.2.5"
    #     external_ip_ru1-a1 = "${yandex_vpc_address.external-address-a1.external_ipv4_address[0].address}"
    #     ip_ru1-a2 = "192.168.2.15"
    #     external_ip_ru1-a2 = "${yandex_vpc_address.external-address-a2.external_ipv4_address[0].address}"
    #     ip_ru1-b1 = "192.168.1.5"
    #     external_ip_ru1-b1 = "${yandex_vpc_address.external-address-b1.external_ipv4_address[0].address}"
    #     ip_ru1-b2 = "192.168.1.15"
    #     external_ip_ru1-b2 = "${yandex_vpc_address.external-address-b2.external_ipv4_address[0].address}"
  }


  scale_policy {
    fixed_scale {
      size = 5
    }
  }

  allocation_policy {
    zones = ["ru-central1-a"]
  }

  deploy_policy {
    max_unavailable = 2
    max_creating    = 2
    max_expansion   = 2
    max_deleting    = 2
  }

  load_balancer {
    target_group_name = "target-group-for-lb"
  }

}



#---------------------------LOad Balancer for group-vm------------------------------------------------------------------

resource "yandex_lb_network_load_balancer" "lb-for-webapp" {
  name = "lb-webapp"

  listener {
    name     = "listener-web-servers"
    port     = 80
    protocol = "tcp"
    external_address_spec {
      ip_version = "ipv4"
    }
  }

  attached_target_group {
    target_group_id = yandex_compute_instance_group.group1.load_balancer.0.target_group_id

    healthcheck {
      name                = "http"
      interval            = 2
      timeout             = 1
      unhealthy_threshold = 2
      healthy_threshold   = 2
      http_options {
        port = 80
        path = "/"
      }
    }
  }
}



#----------------------Static IP addresses-------------------------------------------------------------------------------
#-----Block which get static ip address each server in server-group-------

# resource "yandex_vpc_address" "external-address-a1" {
#   name = "static-ip-addr1"
#
#   external_ipv4_address {
#     zone_id = "ru-central1-a"
#   }
# }
#
# resource "yandex_vpc_address" "external-address-a2" {
#   name = "static-ip-addr2"
#
#   external_ipv4_address {
#     zone_id = "ru-central1-a"
#   }
# }
#
# resource "yandex_vpc_address" "external-address-b1" {
#   name = "static-ip-addr3"
#
#   external_ipv4_address {
#     zone_id = "ru-central1-b"
#   }
# }
#
# resource "yandex_vpc_address" "external-address-b2" {
#   name = "static-ip-addr4"
#
#   external_ipv4_address {
#     zone_id = "ru-central1-b"
#   }
# }
#


#---------------It can be Bastion server for PostgreSQL CLUster-------------------------------


# resource "yandex_compute_instance" "db_instance" {
#   name        = "database-vm"
#   platform_id = "standard-v1"
#   zone        = "ru-central1-a"
#
#   resources {
#     cores  = 2
#     memory = 4
#   }
#
#   boot_disk {
#     initialize_params {
#       image_id = var.centos_image_id # ОС (Centos, 7)
#     }
#   }
#
#   network_interface {
#     index     = 1
#     subnet_id = yandex_vpc_subnet.private-subnet-for-db.id
#     nat       = false #Disable nat to won't create public ip for this VM
#   }
#
#   metadata = {
#     foo      = "bar"
#     ssh-keys = "ubuntu:${file("/etc/ssh/k8s_keys.pub")}"
#   }
#
# }
#

#----------------------------------------PostgreSQL cluster (without Bastion server)-------------------------------------------------------------

resource "yandex_mdb_postgresql_cluster" "postgresql-cluster" {
  name                = "postgresql"
  description         = "PostgreSQL Cluster"
  environment         = "PRESTABLE"
  network_id          = yandex_vpc_network.vpc-for-pg-cluster.id
  security_group_ids  = [yandex_vpc_security_group.pgsql-sg.id]
  deletion_protection = false

  config {
    version = 15
    resources {
      resource_preset_id = "s2.micro"
      disk_size          = 20
      disk_type_id       = "network-ssd"
    }

  }

  host {
    zone             = "ru-central1-b"
    name             = "host_name_a"
    priority         = 2
    subnet_id        = yandex_vpc_subnet.subnet-for-pg-cluster.id
    assign_public_ip = true
  }
}

resource "yandex_mdb_postgresql_user" "user-lead" {
  cluster_id = yandex_mdb_postgresql_cluster.postgresql-cluster.id
  name       = "nikitaops"
  password   = "nikita999"
}


resource "yandex_mdb_postgresql_database" "db1" {
  cluster_id = yandex_mdb_postgresql_cluster.postgresql-cluster.id
  name       = "db1"
  owner      = yandex_mdb_postgresql_user.user-lead.name
}


#   host {
#     zone                    = "ru-central1-b"
#     name                    = "host_name_b"
#     replication_source_name = "host_name_c"
#     subnet_id               = yandex_vpc_subnet.b.id
#   }
#   host {
#     zone      = "ru-central1-c"
#     name      = "host_name_c"
#     subnet_id = yandex_vpc_subnet.c.id
#   }
#   host {
#     zone      = "ru-central1-c"
#     name      = "host_name_c_2"
#     subnet_id = yandex_vpc_subnet.c.id
#   }

