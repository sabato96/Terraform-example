variable "project_id" { }


variable "credentials_file" { }


variable "region" {

  default = "us-central1"

}

variable "cluster_name" {
  
  description = "Nome del cluster"

  default = "k8s-cluster"

}

variable "env_name" {

  default = "prod"

}

variable "network" { 

  default = "k8s-network"

}

variable "subnetwork" {

  default = "k8s-subnet"

}

variable "ip_range_pods_name" {

  default     = "ip-range-pods"

}


variable "ip_range_services_name" {

  default     = "ip-range-services"

}


variable "zone" {

  default = "us-central1-b"
}
