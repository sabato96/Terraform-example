terraform {
  required_providers {
    google = {
      source = "hashicorp/google"
      version = "~> 3.42.0"
    }
  }
}

provider "google" {
  credentials = file(var.credentials_file)

  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# I moduli ci permettono di raccogliere risorse multiple in un unico container. Questo permette di riutilizzare tali moduli più volte anche per diversi progetti.
# In linea di principio è possibile creare un modulo da qualsiasi combinazione di risorse. Si raccomanda di utilizzare i moduli solo quando strettamente necessario.





# Il modulo "gke_auth" permette di configurare l'autenticazione e le autorizzazioni del cluster ed aiuta l'integrazione con kubectl e in particolare con il file kubeconfig.
# L'autenticazione avviene attraverso un token OpenID, reperito sotto forma di un file kubeconfig.

module "gke_auth" {
  source = "terraform-google-modules/kubernetes-engine/google//modules/auth" 
  depends_on   = [module.gke]
  project_id   = var.project_id
  location     = module.gke.location
  cluster_name = module.gke.name
}

# "local_file" esporta il file generato in locale
# In tal caso il file oggetto dell'export è il kubeconfig file generato dal modulo gke_auth.


resource "local_file" "kubeconfig" {
  content  = module.gke_auth.kubeconfig_raw
  filename = "kubeconfig-${var.env_name}"
}



# Il modulo gcp-network seve a creare una VPC personalizzata dedicata al cluster che andremo a creare.
# Il modulo permette inoltre di configurare le subnet. In tal caso il modulo crea una sottorete con blocco indirizzi ip locali "10.10.0.0/16"
# per un totale di 65536 possibili indirizzi ip (si veda CIDR notation)

# Secondary ranges .-....

# .......


module "gcp-network" {
  source       = "terraform-google-modules/network/google"
  version      = "~> 2.5"
  project_id   = var.project_id
  network_name = "${var.network}-${var.env_name}"
  subnets = [
    {
      subnet_name   = "${var.subnetwork}-${var.env_name}"
      subnet_ip     = "10.10.0.0/16"
      subnet_region = var.region
    },
  ]
  secondary_ranges = {
    "${var.subnetwork}-${var.env_name}" = [
      {
        range_name    = var.ip_range_pods_name
        ip_cidr_range = "10.20.0.0/16"
      },
      {
        range_name    = var.ip_range_services_name
        ip_cidr_range = "10.30.0.0/16"
      },
    ]
  }
}


# Il modulo gke è il modulo che effettua il deployment effettivo del cluster kubernetes su gke.
# In tal caso il cluster risulta essere regionale






module "gke" {
  source                 = "terraform-google-modules/kubernetes-engine/google//modules/private-cluster"
  project_id             = var.project_id
  name                   = "${var.cluster_name}-${var.env_name}"
  regional               = true
  region                 = var.region
  network                = module.gcp-network.network_name
  subnetwork             = module.gcp-network.subnets_names[0]
  ip_range_pods          = var.ip_range_pods_name
  ip_range_services      = var.ip_range_services_name
  node_pools = [
    {
      name                      = "node-pool"
      machine_type              = "e2-medium"
      node_locations            = "us-central1-a,us-central1-b"
      min_count                 = 1
      max_count                 = 2
      disk_size_gb              = 30
    },
  ]
}


############### Istanza cloudsql + istanza wordpress collegate su una sottorete differente

# Creazione VPC dedicata

resource "google_compute_network" "wp-net" {

  name = "wp-network"
  routing_mode = "GLOBAL"
  auto_create_subnetworks = true

}

# Alloco blocco di indirizzi ip 

resource "google_compute_global_address" "private_ip_block" {
  name         = "private-ip-block"
  purpose      = "VPC_PEERING"
  address_type = "INTERNAL"
  ip_version   = "IPV4"
  prefix_length = 20
  network       = google_compute_network.wp-net.self_link
}

# Attivo PRIVATE SERVICES ACCESS per permettere alle macchine di comunicare utilizzando indirizzi ip privati

resource "google_service_networking_connection" "private-conn" { 

  network = google_compute_network.wp-net.self_link
  service = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_block.name]


}

# Regole firewall wp-net vpc

resource "google_compute_firewall" "wp-fire" { 

  name = "wp-firewall"
  network = google_compute_network.wp-net.name

  allow {

    protocol = "icmp"

  }

  allow {

    protocol = "tcp"
    ports = ["22","80"]

  }

  target_tags = ["web"]
}

# Creo regola firewall per accettare richieste di wp-serv al database su porta 3306 - mysql

resource "google_compute_firewall" "wp-fire-db" { 

  name = "db-firewall"
  network = google_compute_network.wp-net.name

  allow {

    protocol = "tcp"
    ports = ["3306"] 

  }

  source_tags = ["web"]
}

# Creazione istanza MYSQL

resource "google_sql_database_instance" "master-db" {

  name = "db-wp-instance"
  database_version = "MYSQL_5_7"
  region = var.region
  depends_on = [google_service_networking_connection.private-conn]
  settings {

    tier = "db-n1-standard-2"
    activation_policy = "ALWAYS"
    availability_type = "REGIONAL"
    disk_size = 30

    backup_configuration {

      enabled = true
      binary_log_enabled = true

    }

    ip_configuration {

      ipv4_enabled = false
      private_network = google_compute_network.wp-net.self_link

    }

  }

}


# creo database in CLOUDSQL instance

resource "google_sql_database" "wp-db" {

  name = "wp-database"
  instance = google_sql_database_instance.master-db.name
}

# Creo utente database

resource "google_sql_user" "db-user" { 

  name = "user"
  instance = google_sql_database_instance.master-db.name
  password = "password"
}


# Creo istanza per server wordpress

resource "google_compute_instance" "wp-server" { 

  name = "wp-ser"
  machine_type = "e2-medium"
  depends_on = [google_service_networking_connection.private-conn]
  tags = ["web"]
  boot_disk { 

    initialize_params {

      image = "ubuntu-1804-lts"

    }

  }

  network_interface {

    network = google_compute_network.wp-net.self_link

    access_config {
    }
  }

  metadata_startup_script = file("./startup_wordpress.sh") 




}











