---
date: "2016-03-08T13:07:35Z"
draft: true
title: Deploying Hugo with Vagrant and SaltStack
tags:
  - SaltStack
  - Vagrant
  - HUGO
---

To setup this blog, I wanted to use something that is both easy to use via the terminal and caters to my preference for everything text-based.
After some dabbling around with both Jekyll and Octopress, I decided to use [Hugo](http://gohugo.io/) mainly due to its LiveReload functionality.
<!--more-->

# How does it look like?
You're looking at it right now.

# Why Vagrant + SaltStack?
> Because I can  

On a more serious note, I like the idea of having the same development environment on all machines, independent of their OS.


# Hacking locally
To start hacking locally, you'll need some prerequisites:

- Vagrant
- Virtualbox

If you want live updates as you save your blog entries, you'll need

- rsync
- vagrant plugin vagrant-gatling-rsync

(more on that [later]({{< relref "#live-reloading" >}}))

If you want everything installed via CLI and you're on Windows, I recommend [Chocolatey](https://chocolatey.org/). After installing it, you can simply execute 

```
cinst virtualbox vagrant rsync -y
```

If you're on MacOS, you can install it via [homebrew](http://brew.sh/):
```
brew cask install virtualbox vagrant -y
```


# The setup
The Vagrantfile bootstraps a Ubuntu VM with a dedicated IP that you can connect to from your host machine (172.17.0.100).  
This VM will sync 2 folders, namely the Hugo folder for the actual blog and the salt folder for bootstrapping.
The salt folder contains a [SaltStack](https://docs.saltstack.com/en/getstarted/index.html) state to install and start Hugo.


# Live reloading
In order for [LiveReload](https://gohugo.io/extras/livereload/) to work inside a virtual machine, I had to work around an issue with shared folders (See https://www.virtualbox.org/ticket/9069 and https://github.com/mitchellh/vagrant/issues/351#issuecomment-1339640). This meant that instead of relying on vagrant's default shared folder implementation for VirtualBox, I used [rsync](https://www.vagrantup.com/docs/synced-folders/rsync.html) instead.  
After switching to rsync I had to call `vagrant rsync-auto` after each `vagrant up` which I did not like. To remedy this I used the plugin [vagrant-gatling-rsync](https://github.com/smerrill/vagrant-gatling-rsync) which automatically starts a rsync-watch after each `vagrant up` or `vagrant reload`.
