---
date: "2016-03-08T13:07:35Z"
draft: false
title: How to deploy a blog the convoluted way
tags:
  - SaltStack
  - Vagrant
  - HUGO
  - Wercker
---

To setup this blog, I wanted to use something that is both easy to use via the terminal and caters to my preference for everything text-based.
After some dabbling around with both Jekyll and Octopress, I decided to use Hugo mainly due to its LiveReload functionality and its extremely well written documentation.
<!--more-->

## How does it look like?
You're looking at it right now.

## How do you write a new blog post?
```bash
git clone git@github.com:Oro/blog.oro.nu.git 
cd blog.oro.nu
vagrant up
vim hugo/content/post/newpost.md # This is the difficult part
git add newpost.md
git commit -m "New blog post"
git push
```

## Which systems or programs are involved?
[Vagrant](https://www.vagrantup.com/)
: To create a portable development environment

[VirtualBox](https://www.virtualbox.org/)
: Does the heavy lifting of the VMs

[SaltStack](https://docs.saltstack.com/en/getstarted/index.html)
: Provisions Hugo inside the VM

[Hugo](http://gohugo.io/)
: Used to build the site

[Wercker](http://wercker.com/)
: Compiles and deploys the site to GitHub Pages

[GitHub](https://github.com/) and [GitHub Pages](https://pages.github.com/)
: Holds the markdown that is built as well as the static pages themselves

## Why xyz?
> Because I can.
> 
> -- <cite>Marco Orovecchia</cite> - Probably not the first to say this

On a more serious note, I like the idea of having the same development environment on all machines, independent of their OS. Also because I like to tinker around.

## Hacking locally
To start hacking locally, you'll need some prerequisites:

- Vagrant
- Virtualbox

If you want live updates as you save your blog entries, you'll need

- rsync
- vagrant plugin vagrant-gatling-rsync

(more on that [later]({{< relref "#live-reloading" >}}))

If you want everything installed via CLI and you're on Windows, I recommend [Chocolatey](https://chocolatey.org/). After installing it, you can simply execute 

```bash
cinst virtualbox vagrant rsync -y
```

If you're on MacOS, you can install it via [homebrew](http://brew.sh/):
```bash
brew cask install virtualbox vagrant -y
```


## The setup
The Vagrantfile[^1] bootstraps a Ubuntu VM with a dedicated IP that you can connect to from your host machine (172.17.0.100).  
2 folders are synced to this VM, namely the Hugo folder for the actual blog and the salt folder for bootstrapping.
The salt folder contains a SaltStack state[^2] to install and start Hugo.

After the bootstrapping is finished, you can access Hugo at http://172.17.0.100:1313/ .


## Live reloading
In order for [LiveReload](https://gohugo.io/extras/livereload/) to work inside a virtual machine, I had to work around an issue with shared folders (See [virtualbox-9069](https://www.virtualbox.org/ticket/9069) and [vagrant-351](https://github.com/mitchellh/vagrant/issues/351)). This meant that instead of relying on Vagrant's default shared folder implementation for VirtualBox, I used [rsync](https://www.vagrantup.com/docs/synced-folders/rsync.html) instead.  
After switching to rsync I had to call `vagrant rsync-auto` after each `vagrant up` which I did not like. To remedy this I used the plugin [vagrant-gatling-rsync](https://github.com/smerrill/vagrant-gatling-rsync) which automatically starts a rsync-watch after each `vagrant up` or `vagrant reload`.

## Deployment
Deploying the whole side - including build - is done by Wercker and the associated Wercker file[^3] in the repository. Every push to master triggers a build at [my Wercker app](https://app.wercker.com/#applications/56df0e2f9d5cf1b5734fd1cd) and, if successful, deploys it immediately afterwards.

[^1]: https://github.com/Oro/blog.oro.nu/blob/master/Vagrantfile
[^2]: https://github.com/Oro/blog.oro.nu/blob/master/salt/roots/hugo.sls
[^3]: https://github.com/Oro/blog.oro.nu/blob/master/wercker.yml
