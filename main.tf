terraform {
  required_providers {
    harvester = {
      source  = "harvester/harvester"
      version = ">= 0.6.0"
    }
  }
}

provider "harvester" {
  kubeconfig = "/home/Harvester.yaml"
}

# INPUTS
variable "image_folder" {
  type = string
}

variable "image_file" {
  type = string
}

variable "server_ip" {
  default = "10.30.1.40"
}

variable "server_user" {
  default = "ubuntu"
}

variable "remote_folder" {
  default = "/home/ubuntu/images"
}

########################################
# STEP 1: COPY IMAGE TO SERVER
########################################
resource "null_resource" "copy_image" {
  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<EOT
      set -e
      echo "Copying ${var.image_file}..."

      ssh ${var.server_user}@${var.server_ip} "mkdir -p ${var.remote_folder}"

      scp "${var.image_folder}/${var.image_file}" \
      ${var.server_user}@${var.server_ip}:"${var.remote_folder}/"

      ssh ${var.server_user}@${var.server_ip} \
      "ls ${var.remote_folder}/${var.image_file}"
    EOT
  }
}

########################################
# STEP 2: START HTTP SERVER (NOHUP)
########################################
resource "null_resource" "http_server" {
  depends_on = [null_resource.copy_image]

  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<EOT
      ssh ${var.server_user}@${var.server_ip} '
        if ! lsof -i :9000 >/dev/null 2>&1; then
          echo "Starting HTTP server..."
          cd ${var.remote_folder}
          nohup python3 -m http.server 9000 > server.log 2>&1 &
          sleep 3
        else
          echo "HTTP server already running"
        fi
      '
    EOT
  }
}

########################################
# STEP 3: UPLOAD IMAGE TO HARVESTER
########################################
resource "harvester_image" "image" {
  depends_on = [null_resource.http_server]

  name = trim(
    replace(
      replace(
        replace(
          replace(lower(var.image_file), ".iso", ""),
          ".img", ""
        ),
        "_", "-"
      ),
      ".", "-"
    ),
    "-"
  )

  namespace    = "paradigmai"
  display_name = var.image_file
  source_type  = "download"

  url = "http://${var.server_ip}:9000/${var.image_file}"

  lifecycle {
    prevent_destroy = true
  }
}
