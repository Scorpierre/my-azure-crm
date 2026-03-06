# 1. On définit quel logiciel on télécharge
terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

# 2. On configure le logiciel (C'est ici qu'il te manquait "features")
provider "azurerm" {
  features {} 
  resource_provider_registrations = "none"
}

# --- VARIABLES ---
variable "location" {
  default = "francecentral"
}

variable "prefix" {
  default = "CRM-PROD"
}

# --- RESSOURCES ---

resource "azurerm_resource_group" "rg" {
  name     = "RG-${var.prefix}"
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = "vnet-${var.prefix}"
  address_space       = ["10.0.0.0/16"]
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
}

resource "azurerm_subnet" "snet_web" {
  name                 = "snet-web"
  resource_group_name  = azurerm_resource_group.rg.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

# --- SÉCURITÉ (NSG) ---

resource "azurerm_network_security_group" "nsg_web" {
  name                = "nsg-web-rules"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  # Porte d'administration (SSH)
  security_rule {
    name                       = "AllowSSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  # Porte du site web (HTTP)
  security_rule {
    name                       = "AllowHTTP"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Liaison du NSG au Subnet
resource "azurerm_subnet_network_security_group_association" "link_nsg" {
  subnet_id                 = azurerm_subnet.snet_web.id
  network_security_group_id = azurerm_network_security_group.nsg_web.id
}

# 1. Créer une adresse IP Publique (pour ton Mac)
resource "azurerm_public_ip" "pip" {
  name                = "pip-crm"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name
  allocation_method   = "Static"
  sku                 = "Standard"
    }

# 2. Créer la Carte Réseau (NIC)
resource "azurerm_network_interface" "nic" {
  name                = "nic-crm"
  location            = azurerm_resource_group.rg.location
  resource_group_name = azurerm_resource_group.rg.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.snet_web.id # On la branche au 1er étage !
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.pip.id   # On lui donne son IP publique
  }
}

# 3. La Machine Virtuelle Linux (La pièce maîtresse)
resource "azurerm_linux_virtual_machine" "vm" {
  name                = "vm-crm-student"
  resource_group_name = azurerm_resource_group.rg.name
  location            = azurerm_resource_group.rg.location
  size                = "Standard_B2ats_v2"
  admin_username      = "adminuser"

  admin_ssh_key {
    username   = "adminuser"
    public_key = file("~/.ssh/id_azure.pub")
  }

  network_interface_ids = [azurerm_network_interface.nic.id]

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts"
    version   = "latest"
  }

  disable_password_authentication = true
}


# 4. Afficher l'IP à la fin du déploiement
output "public_ip_address" {
  value = azurerm_public_ip.pip.ip_address
}
