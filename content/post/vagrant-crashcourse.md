---
date: "2016-06-23T12:08:20Z"
draft: false
title: Vagrant Crash Course
tags:
  - Vagrant
  - Crash Course
---

## What is Vagrant?
Vagrant is a tool to create and maintain reproducible development environments.

This post will help you getting started with Vagrant and goes into more detail about the preliminaries in my [SaltStack Crash Course]({{< relref "saltstack-crashcourse.md" >}})
<!--more-->

## Prerequisites
To get started, you will need the following installed:

- [Vagrant](https://www.vagrantup.com/)
- [VirtualBox](https://www.virtualbox.org/)

## Reproducible development environments?
Vagrant helps you in setting up a clean environment for your local dev box.
For instance, consider your development environment needing Apache and PostgreSQL.  
Instead of installing it locally and needing to repeat that for each and every box you have (or worse, for every additional developer), you can just `vagrant up` and get a fully working environment within seconds.

## Why Vagrant?

Vagrant is a great tool to create disposable environments. Say for instance I would like to create a new Salt state and test it out, I might spin up several vagrant boxes just to make sure that the state works.  
I also like to use it to play around with new OS' and tools. For instance, I'd love to check out [NixOS](https://nixos.org/wiki/Vagrant_boxes) within a VM.

## Architecture
### Providers

Providers are doing the hard work for Vagrant. They are responsible for setting up the VM, the disks, networking etc.. 

### Provisioners

Provisioners are also doing the hard work for Vagrant. They allow you to configure the VM after it has booted, e.g. to install and configure software on top of the provided Box.

### Boxes

Boxes are basically VM images that Vagrant can use to bootstrap different OS in your environment. They are mostly supplied by the community and are listed on the [Public Vagrant Box catalog](https://atlas.hashicorp.com/boxes/search).

### Vagrantfiles

The Vagrantfile is used to describe the environment you want to bootstrap. It contains information which Box to use, which Provier(s) and which Provisioner(s) and its instructions. With a Vagrantfile within a project repository, you can clone the repository and use `vagrant up` to get up and running with the project (most of the time anyway).

## Do It Yourself
To get immediately started, install the prerequisites, `cd` into a new folder and type the following:
```bash
vagrant init ubuntu/trusty64
vagrant up
```
This will create a new VM with Ubuntu 14.04 in which you can remote into via
```bash
vagrant ssh
```
After you are done, you can use the following to get rid of your machine:
```bash
vagrant destroy
```

## Demo
```bash
git clone https://github.com/Oro/vagrant-crashcourse.git
cd vagrant-crashcourse
vagrant up
```

The first time you execute `vagrant up` it might take several minutes, depending on your Internet connection. Subsequent executions will be much faster since the boxes will be cached on your local machine.  
After the VMs started successfully, you'll be able to open http://localhost:8080/ and access your local Apache. You can also login to the VM via
```bash
vagrant ssh
```

Did I also mention that the project's files are mounted inside the VM? This allows you to use your local text editor to edit files and immediately see changes within your deployed application (Shameless plug: This is how this blog is maintained, see [How to deploy a blog the convoluted way]({{< relref "deploying-hugo-with-vagrant-and-saltstack.md" >}}))
## Further Reading
[Vagrant Documentation](https://www.vagrantup.com/docs/)

