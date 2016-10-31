# -*- mode: ruby -*-
# vi: set ft=ruby :

Vagrant.configure(2) do |config|
  config.vm.box = "ubuntu/trusty64"
  config.vm.network "private_network", ip: "172.17.0.100"
  config.vm.synced_folder "salt/roots/", "/srv/salt/", type: "rsync"
  config.vm.synced_folder "hugo/", "/var/hugo", type: "rsync",
    rsync__exclude: [".git/", ".vagrant"]
  config.vm.provision :salt , run: "always"do |salt|
    salt.minion_config = "salt/minion"
    salt.masterless = true
    salt.run_highstate = true
  end
  config.vm.post_up_message = "Hugo should now be available at http://172.17.0.100:1313"
end
