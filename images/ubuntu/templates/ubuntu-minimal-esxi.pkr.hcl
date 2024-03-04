packer {
  //Need vmware plugin here, either vmware-iso or vsphere-iso
}

locals {
  image_os = "ubuntu22"

  toolset_file_name = "toolset-2204.json"

  image_folder            = "/imagegeneration"
  helper_script_folder    = "/imagegeneration/helpers"
  installer_script_folder = "/imagegeneration/installers"
  imagedata_file          = "/imagegeneration/imagedata.json"

  managed_image_name = var.managed_image_name != "" ? var.managed_image_name : "packer-${var.image_os}-${var.image_version}"
}

variable "image_version" {
  type    = string
  default = "dev"
}

variable "install_password" {
  type      = string
  default   = ""
  sensitive = true
}

variable "builder_host" {
  type    = string
  default = ""
}

variable "builder_host_username" {
  type    = string
  default = ""
}

variable "builder_host_password" {
  type    = string
  default = ""
  sensitive = true
}

variable "builder_host_datastore" {
  type    = string
  default = ""
}

variable "builder_host_portgroup" {
  type    = string
  default = ""
}

variable "builder_host_output_dir" {
  type    = string
  default = ""
}

variable "dockerhub_login" {
  type    = string
  default = ""
}

variable "dockerhub_password" {
  type    = string
  default = ""
  sensitive = true
}

variable "iso_local_path" {
  type    = string
  default = ""
}

variable "iso_checksum" {
  type    = string
  default = ""
}

variable "numvcpus" {
  type    = string
  default = "4"
}

variable "ramsize" {
  type    = string
  default = "16384"
}

variable "vm_name" {
  type    = string
  default = ""
}

variable "ovftool_deploy_vcenter" {
  type    = string
  default = ""
}

variable "ovftool_deploy_vcenter_username" {
  type    = string
  default = ""
}

variable "ovftool_deploy_vcenter_password" {
  type    = string
  default = ""
  sensitive = true
}

// Need vmware source section here

build {
  sources = ["source.azure-arm.build_image"]

  // Create folder to store temporary data
  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    inline          = ["mkdir ${local.image_folder}", "chmod 777 ${local.image_folder}"]
  }

  // Add apt wrapper to implement retries
  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "${path.root}/../scripts/build/configure-apt-mock.sh"
  }

  // Install MS package repos, Configure apt
  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = [
      "${path.root}/../scripts/build/install-ms-repos.sh",
      "${path.root}/../scripts/build/configure-apt.sh"
    ]
  }

  // Configure limits
  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "${path.root}/../scripts/build/configure-limits.sh"
  }

  provisioner "file" {
    destination = "${local.helper_script_folder}"
    source      = "${path.root}/../scripts/helpers"
  }

  provisioner "file" {
    destination = "${local.installer_script_folder}"
    source      = "${path.root}/../scripts/build"
  }

  provisioner "file" {
    destination = "${local.image_folder}"
    sources     = [
      "${path.root}/../assets/post-gen",
      "${path.root}/../scripts/tests"
    ]
  }

  provisioner "file" {
    destination = "${local.installer_script_folder}/toolset.json"
    source      = "${path.root}/../toolsets/${local.toolset_file_name}"
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    inline          = ["mv ${local.image_folder}/post-gen ${local.image_folder}/post-generation"]
  }

  // Generate image data file
  provisioner "shell" {
    environment_vars = ["IMAGE_VERSION=${var.image_version}", "IMAGEDATA_FILE=${local.imagedata_file}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/configure-image-data.sh"]
  }

  // Create /etc/environment, configure waagent etc.
  provisioner "shell" {
    environment_vars = ["IMAGE_VERSION=${var.image_version}", "IMAGE_OS=${local.image_os}", "HELPER_SCRIPTS=${local.helper_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/configure-environment.sh"]
  }

  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive", "HELPER_SCRIPTS=${local.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${local.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/install-apt-vital.sh"]
  }

  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive", "HELPER_SCRIPTS=${local.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${local.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/install-powershell.sh"]
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPTS=${local.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${local.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} pwsh -f {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/Install-PowerShellModules.ps1"]
  }

  provisioner "shell" {
    environment_vars = ["DEBIAN_FRONTEND=noninteractive", "HELPER_SCRIPTS=${local.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${local.installer_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = [
      "${path.root}/../scripts/build/install-git.sh",
      "${path.root}/../scripts/build/install-git-lfs.sh",
      "${path.root}/../scripts/build/install-github-cli.sh",
      "${path.root}/../scripts/build/install-zstd.sh"
    ]
  }

  provisioner "shell" {
    execute_command   = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    expect_disconnect = true
    inline            = ["echo 'Reboot VM'", "sudo reboot"]
  }

  provisioner "shell" {
    execute_command     = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    pause_before        = "1m0s"
    scripts             = ["${path.root}/../scripts/build/cleanup.sh"]
    start_retry_timeout = "10m"
  }

  provisioner "shell" {
    environment_vars = ["HELPER_SCRIPT_FOLDER=${local.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${local.installer_script_folder}", "IMAGE_FOLDER=${local.image_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/configure-system.sh"]
  }

  provisioner "shell" {
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    inline          = ["sleep 30", "/usr/sbin/waagent -force -deprovision+user && export HISTSIZE=0 && sync"]
  }

}
