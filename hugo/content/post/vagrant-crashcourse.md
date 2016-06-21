---
date: "2016-06-21T11:28:20Z"
draft: true
title: Vagrant Crash Course
tags:
  - Vagrant
  - Crash Course
---

## What is Vagrant?
Vagrant is a tool to create and maintain reproducible development environments.

This post will help you getting started with Vagrant and goes into more detail about the preliminaries in [SaltStack Crash Course]({{< relref "saltstack-crashcourse.md" >}})
<!--more-->

## Prerequisites
To get started, you will need the following installed:

- [Vagrant](https://www.vagrantup.com/)
- [VirtualBox](https://www.virtualbox.org/)

## Reproducible development environments?
Vagrant helps you in setting up a clean environment for your local dev box.
For instance, consider your development environment needing Apache and PostgreSQL.  
Instead of installing it locally and needing to repeat that for each and every box you have (or worse, for every additional developer), you can just `vagrant up` and get a fully working environment within seconds.


## Getting Started
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

