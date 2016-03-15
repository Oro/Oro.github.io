---
date: "2016-03-11T13:42:02Z"
draft: false
title: SaltStack Crash Course
tags:
  - SaltStack
  - Vagrant
---

## What is SaltStack?
SaltStack is a configuration management tool.  
It allows you to manage thousands of servers (or just one) from a central location.

This post will help you getting started with several VMs you can use to get to know SaltStack.
After you've followed these instructions, you will get one Salt Master and 2 Salt Minions on which you can execute your commands.
<!--more-->

## Prerequisites
- [Vagrant](https://www.vagrantup.com/)
- [VirtualBox](https://www.virtualbox.org/)

## Getting Started
```bash
git clone https://github.com/Oro/salt-crashcourse.git
cd salt-crashcourse
vagrant up
```
The first time you execute `vagrant up` it might take several minutes, depending on your internet connection. Subsequent executions will be much faster since the boxes will be cached on your local machine.  
After the VMs started successfully, you can connect to the Salt master via
```bash
vagrant ssh master
```
Salt commands on this machine require sudo permissions, so switch to root via 
```bash
sudo su
```

Now you can execute salt commands. Let's try an execution module, [test.ping](https://docs.saltstack.com/en/latest/ref/modules/all/salt.modules.test.html#salt.modules.test.ping) on all VMs:
```bash
salt '*' test.ping
```

SaltStack can issue commands two different ways, via [execution modules](https://docs.saltstack.com/en/latest/ref/modules/all/index.html) and via [state modules](https://docs.saltstack.com/en/latest/ref/states/all/index.html).
Modules can be called for any machine via the Salt master, or for the local machine via `salt-call`. 
## Salt CLI
```
salt '*' test.ping
\__/ \_/ \_______/
  |   |      |
  |   |      \- The execution module to run
  |   |
  |   \- The minions to target (do not forget to enclose an asterisk
  |      with quotes)
  |
  \- The salt command itself
```
[^1]

## Salt State Modules
SaltStack files are written (per default) in [YAML](https://docs.saltstack.com/en/latest/topics/yaml/).  
The `top.sls` for state modules consists of 3 elements and is used to target specific minions with specific states.
```
# salt/roots/top.sls
base:                      # Environment
  '*':                     # Target
    - my_own_git_state     # State
```
A state consists of an ID (that is unique across all state modules), the module to execute and its parameters.
```
# salt/roots/my_own_git_state.sls
my_own_git_state:          # Unique ID
  pkg.installed:           # State Module
    - name: git            # Parameter
```

With 2 files (`top.sls` and `my_own_git_state.sls`) inside salt/roots/ you can now go ahead and execute
```
salt '*' state.apply 
```
This will now make sure that git is installed on all 3 machines. On the master git is already installed, hence SaltStack will not change anything. On the two minions however git alongside its dependencies will be installed via apt-get.
Now imagine you do not only want git, but also a git repository cloned. This can be easily done by appending the git.latest state module to our state file so that it looks as follows:
```
my_own_git_state:          # Unique ID
  pkg.installed:           # State Module
    - name: git            # Parameter
  git.latest:
    - name: https://github.com/Oro/salt-crashcourse.git 
    - target: /srv/crashcourse
```
And now let's again apply the state to all VMs:
```
salt '*' state.apply 
```

## Further Reading
If you want to know more, I recommend the excellent [SaltStack Tutorials](https://docs.saltstack.com/en/latest/topics/tutorials/index.html), which goes far more in-depth.

[^1]: Generated with [explain](https://github.com/vain/explain)
