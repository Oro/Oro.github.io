+++
title = "Hetzner Cloud with NixOS"
author = ["Marco Orovecchia"]
date = 2020-04-09T15:57:00+02:00
tags = ["nixos", "hetzner", "nixops"]
draft = false
description = "Create a new Hetzner cloud host with the following cloud-init script and you have a new NixOS-machine with nixos-unstable. This uses latest nixos-infect."
+++

Create a new Hetzner cloud host with the following cloud-init script and you have a new NixOS-machine with `nixos-unstable`. This uses latest [nixos-infect](https://github.com/elitak/nixos-infect).

```yaml
#cloud-config

runcmd:
  - curl https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect | PROVIDER=hetznercloud NIX_CHANNEL=nixos-unstable bash 2>&1 | tee /tmp/infect.log
```


## Creation via API {#creation-via-api}

Create an API key on Hetzner clouds GUI (Project -> Access -> API Tokens), then you can execute following `POST` requets, e.g. via `curl`:


### First the SSH key: {#first-the-ssh-key}

Substitute :bearer with your bearer token and :sshkey with your ssh-key

```http
POST https://api.hetzner.cloud/v1/ssh_keys HTTP/1.1
Authorization: Bearer :bearer
Content-Type: application/json

{
  "name": "mykey",
  "public_key": ":sshkey"
}
```


### Then the server {#then-the-server}

Again, substitute :bearer with your bearer token

```http
POST https://api.hetzner.cloud/v1/servers HTTP/1.1
Authorization: Bearer :bearer
Content-Type: application/json

{
  "name": "nixos1",
  "server_type": "cx21",
  "location": "nbg1",
  "start_after_create": true,
  "image": "ubuntu-18.04",
  "labels": {"nixos-flavour": "nixos-infect"},
  "ssh_keys": [
    "mykey"
  ],
  "user_data": "#cloud-config\nruncmd:\n- curl https://raw.githubusercontent.com/elitak/nixos-infect/master/nixos-infect | PROVIDER=hetznercloud NIX_CHANNEL=nixos-unstable bash 2>&1 | tee /tmp/infect.log\n",
  "automount": false
}
```

Afterwards, use [nixops](https://releases.nixos.org/nixops/latest/manual/manual.html) to update the server, e.g. via a `configuration.nix` as follows (again, substitute :sshkey and :ipaddress with the newly created host's IP )

```nix
{
  network.description = "hetzner";

  nixos1 = { config, lib, pkgs, ... }: {
    deployment.targetHost = ":ipaddress";
    users.users.root.openssh.authorizedKeys.keys = [
      ":sshkey"
    ];

    imports = [
      <nixpkgs/nixos/modules/profiles/qemu-guest.nix>
      <nixpkgs/nixos/modules/profiles/hardened.nix>
      <nixpkgs/nixos/modules/profiles/headless.nix>
    ];

    fileSystems."/" = {
      device = "/dev/sda1";
      fsType = "ext4";
    };

    nix.maxJobs = lib.mkDefault 1;
    boot.loader.grub.enable = true;
    boot.loader.grub.version = 2;
    boot.loader.grub.device = "/dev/sda";
    services.openssh.enable = true;
  };
}
```

Then you can use `nixops create ./configuration.nix -d hetzner` to create the initial deployment and `nixops deploy -d hetzner` to deploy new config
