---
date: "2016-10-25T16:16:20Z"
draft: false
title: Bootstrapping an auto scaling web application within AWS via Kubernetes
tags:
  - Kubernetes
  - Docker
  - Terraform
  - Wercker
---

Bootstrapping an auto scaling web application within AWS via Kubernetes
=======================================================================

Let's create a state-of-the-art deployment pipeline for cloud native applications. In this guide, I'll be using Kubernetes on AWS to bootstrap a load-balanced, static-files only web application. This is serious overkill for such an application, however this will showcase several necessities when designing such a system for more sophisticated applications. This guide assumes you are using OSX. You also need to be familiar with both [homebrew](http://brew.sh/index.html) and AWS.

At the end of this guide, we will have a Kubernetes cluster on which we will automatically deploy our application with each check in. This application will be load balanced (running in 2 containers) and health-checked. Aditionally, different branches will get different endpoints and not affect each other. 
{{< figure src="/img/post/pipeline.gif" alt="gif demonstrating automatic scaling of the cluster" width="100%" >}}

About the tools
---------------

[Kubernetes](http://kubernetes.io/)  
A Google-developed container cluster scheduler

[Terraform](https://www.terraform.io/intro/getting-started/build.html)  
A Hashicorp-developed infrastructure-as-code tool

[Wercker](https://wercker.com/)  
An online CI service, specifically for containers

Getting to know Terraform
-------------------------

To bootstrap Kubernetes, I will be using Kops. Kops internally uses Terraform to bootstrap a Kubernetes cluster. First, I've made sure Terraform is up to date

``` bash
brew update
brew install terraform
```

``` example
Already up-to-date.
```

To make sure my AWS credentials (saved in $HOME/.aws/credentials) were picked up by Terraform, I've created an initial, bare-bones Terraform config (which is pretty much taken verbatim from the [Terraform Getting Started Guide](https://www.terraform.io/intro/getting-started/build.html))

```
provider "aws" {}

resource "aws_instance" "example" {
  ami           = "ami-0d729a60"
  instance_type = "t2.micro"
}
```

planned

``` bash
terraform plan 1-initial
```

``` example
provider.aws.region
  The region where AWS operations will take place. Examples
  are us-east-1, us-west-2, etc.

  Default: us-east-1
  Enter a value: 
Refreshing Terraform state in-memory prior to plan...
The refreshed state will be used to calculate this plan, but
will not be persisted to local or remote state storage.


The Terraform execution plan has been generated and is shown below.
Resources are shown in alphabetical order for quick scanning. Green resources
will be created (or destroyed and then created if an existing resource
exists), yellow resources are being changed in-place, and red resources
will be destroyed. Cyan entries are data sources to be read.

Note: You didn't specify an "-out" parameter to save this plan, so when
"apply" is called, Terraform can't guarantee this is what will execute.

+ aws_instance.example
    ami:                      "ami-0d729a60"
    availability_zone:        "<computed>"
    ebs_block_device.#:       "<computed>"
    ephemeral_block_device.#: "<computed>"
    instance_state:           "<computed>"
    instance_type:            "t2.micro"
    key_name:                 "<computed>"
    network_interface_id:     "<computed>"
    placement_group:          "<computed>"
    private_dns:              "<computed>"
    private_ip:               "<computed>"
    public_dns:               "<computed>"
    public_ip:                "<computed>"
    root_block_device.#:      "<computed>"
    security_groups.#:        "<computed>"
    source_dest_check:        "true"
    subnet_id:                "<computed>"
    tenancy:                  "<computed>"
    vpc_security_group_ids.#: "<computed>"


Plan: 1 to add, 0 to change, 0 to destroy.
```

and applied it

``` bash
terraform apply 1-initial
```

``` example
provider.aws.region
  The region where AWS operations will take place. Examples
  are us-east-1, us-west-2, etc.

  Default: us-east-1
  Enter a value: 
aws_instance.example: Creating...
  ami:                      "" => "ami-0d729a60"
  availability_zone:        "" => "<computed>"
  ebs_block_device.#:       "" => "<computed>"
  ephemeral_block_device.#: "" => "<computed>"
  instance_state:           "" => "<computed>"
  instance_type:            "" => "t2.micro"
  key_name:                 "" => "<computed>"
  network_interface_id:     "" => "<computed>"
  placement_group:          "" => "<computed>"
  private_dns:              "" => "<computed>"
  private_ip:               "" => "<computed>"
  public_dns:               "" => "<computed>"
  public_ip:                "" => "<computed>"
  root_block_device.#:      "" => "<computed>"
  security_groups.#:        "" => "<computed>"
  source_dest_check:        "" => "true"
  subnet_id:                "" => "<computed>"
  tenancy:                  "" => "<computed>"
  vpc_security_group_ids.#: "" => "<computed>"
aws_instance.example: Still creating... (10s elapsed)
aws_instance.example: Still creating... (20s elapsed)
aws_instance.example: Creation complete

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

The state of your infrastructure has been saved to the path
below. This state is required to modify and destroy your
infrastructure, so keep it safe. To inspect the complete state
use the `Terraform show` command.

State path: Terraform.tfstate
```

That looks promising, and with a quick glance at the AWS console I could confirm that Terraform had indeed boostrapped a t2.micro instance in the us-east-1. I destroyed it quickly afterwards to incur little to no costs via

``` bash
terraform destroy -force 1-initial
```

``` example
provider.aws.region
  The region where AWS operations will take place. Examples
  are us-east-1, us-west-2, etc.

  Default: us-east-1
  Enter a value: 
aws_instance.example: Refreshing state... (ID: i-c7bc94f6)
aws_instance.example: Destroying...
aws_instance.example: Still destroying... (10s elapsed)
aws_instance.example: Still destroying... (20s elapsed)
aws_instance.example: Still destroying... (30s elapsed)
aws_instance.example: Destruction complete

Destroy complete! Resources: 1 destroyed.
```

Alright, Terraform looks good, let's get to work
------------------------------------------------

Now that I have a basic understanding of Terraform, let's get to using it. As initially said, we are going to use Kops to bootstrap our cluster, so let's get it installed via the instructions found at [the project's GitHub repo](https://github.com/kubernetes/kops).

``` bash
export GOPATH=$HOME/golang/
mkdir -p $GOPATH
go get -d k8s.io/kops
```

This timed out for me, several times. Running `go get` with `-u` allowed me to rerun the same query again and again. This happened during the time my ISP was having some troubles, so your mileage will vary.

Afterwards, I built the binary

``` bash
make
```

Also, I made sure to already have a hosted zone setup via the AWS console (mine was already setup since I've used Route53 as my domain registrar).

After the compilation was done, I've instructed Kops to output Terraform files for the cluster via

``` bash
~/golang/bin/kops create cluster --zones=us-east-1a dev.k8s.orovecchia.com --state=s3://oro-kops-state
~/golang/bin/kops update cluster --target=terraform dev.k8s.orovecchia.com --state=s3://oro-kops-state
```

``` example
Wrote config for dev.k8s.orovecchia.com to "/Users/Marco/.kube/config"
```

This will create the terraform files in `out/terraform`, setup the Kubernetes config in `~/.kube/config` and store the [state](https://github.com/kubernetes/kops/blob/master/docs/state.md) of Kops inside an S3 bucket. This has the benefit that a) other team members (potentially) can modify the cluster and b) the infrastructure itself can be safely stored within a repository

Let's spawn the cluster

``` bash
terraform plan
```

``` example
Refreshing Terraform state in-memory prior to plan...
The refreshed state will be used to calculate this plan, but
will not be persisted to local or remote state storage.


The Terraform execution plan has been generated and is shown below.
Resources are shown in alphabetical order for quick scanning. Green resources
will be created (or destroyed and then created if an existing resource
exists), yellow resources are being changed in-place, and red resources
will be destroyed. Cyan entries are data sources to be read.

Note: You didn't specify an "-out" parameter to save this plan, so when
"apply" is called, Terraform can't guarantee this is what will execute.

+ aws_autoscaling_group.master-us-east-1a-masters-dev-k8s-orovecchia-com
    arn:                                "<computed>"
    availability_zones.#:               "<computed>"
    default_cooldown:                   "<computed>"
    desired_capacity:                   "<computed>"
    force_delete:                       "false"
    health_check_grace_period:          "300"
    health_check_type:                  "<computed>"
    launch_configuration:               "${aws_launch_configuration.master-us-east-1a-masters-dev-k8s-orovecchia-com.id}"
    max_size:                           "1"
    metrics_granularity:                "1Minute"
    min_size:                           "1"
    name:                               "master-us-east-1a.masters.dev.k8s.orovecchia.com"
    protect_from_scale_in:              "false"
    tag.#:                              "5"
    tag.1033606357.key:                 "k8s.io/dns/internal"
    tag.1033606357.propagate_at_launch: "true"
    tag.1033606357.value:               "api.internal.dev.k8s.orovecchia.com"
    tag.1601041186.key:                 "k8s.io/role/master"
    tag.1601041186.propagate_at_launch: "true"
    tag.1601041186.value:               "1"
    tag.2531097064.key:                 "k8s.io/dns/public"
    tag.2531097064.propagate_at_launch: "true"
    tag.2531097064.value:               "api.dev.k8s.orovecchia.com"
    tag.453089870.key:                  "Name"
    tag.453089870.propagate_at_launch:  "true"
    tag.453089870.value:                "master-us-east-1a.masters.dev.k8s.orovecchia.com"
    tag.48875632.key:                   "KubernetesCluster"
    tag.48875632.propagate_at_launch:   "true"
    tag.48875632.value:                 "dev.k8s.orovecchia.com"
    vpc_zone_identifier.#:              "<computed>"
    wait_for_capacity_timeout:          "10m"

+ aws_autoscaling_group.nodes-dev-k8s-orovecchia-com
    arn:                                "<computed>"
    availability_zones.#:               "<computed>"
    default_cooldown:                   "<computed>"
    desired_capacity:                   "<computed>"
    force_delete:                       "false"
    health_check_grace_period:          "300"
    health_check_type:                  "<computed>"
    launch_configuration:               "${aws_launch_configuration.nodes-dev-k8s-orovecchia-com.id}"
    max_size:                           "2"
    metrics_granularity:                "1Minute"
    min_size:                           "2"
    name:                               "nodes.dev.k8s.orovecchia.com"
    protect_from_scale_in:              "false"
    tag.#:                              "3"
    tag.125196166.key:                  "Name"
    tag.125196166.propagate_at_launch:  "true"
    tag.125196166.value:                "nodes.dev.k8s.orovecchia.com"
    tag.1967977115.key:                 "k8s.io/role/node"
    tag.1967977115.propagate_at_launch: "true"
    tag.1967977115.value:               "1"
    tag.48875632.key:                   "KubernetesCluster"
    tag.48875632.propagate_at_launch:   "true"
    tag.48875632.value:                 "dev.k8s.orovecchia.com"
    vpc_zone_identifier.#:              "<computed>"
    wait_for_capacity_timeout:          "10m"

+ aws_ebs_volume.us-east-1a-etcd-events-dev-k8s-orovecchia-com
    availability_zone:       "us-east-1a"
    encrypted:               "false"
    iops:                    "<computed>"
    kms_key_id:              "<computed>"
    size:                    "20"
    snapshot_id:             "<computed>"
    tags.%:                  "4"
    tags.KubernetesCluster:  "dev.k8s.orovecchia.com"
    tags.Name:               "us-east-1a.etcd-events.dev.k8s.orovecchia.com"
    tags.k8s.io/etcd/events: "us-east-1a/us-east-1a"
    tags.k8s.io/role/master: "1"
    type:                    "gp2"

+ aws_ebs_volume.us-east-1a-etcd-main-dev-k8s-orovecchia-com
    availability_zone:       "us-east-1a"
    encrypted:               "false"
    iops:                    "<computed>"
    kms_key_id:              "<computed>"
    size:                    "20"
    snapshot_id:             "<computed>"
    tags.%:                  "4"
    tags.KubernetesCluster:  "dev.k8s.orovecchia.com"
    tags.Name:               "us-east-1a.etcd-main.dev.k8s.orovecchia.com"
    tags.k8s.io/etcd/main:   "us-east-1a/us-east-1a"
    tags.k8s.io/role/master: "1"
    type:                    "gp2"

+ aws_iam_instance_profile.masters-dev-k8s-orovecchia-com
    arn:             "<computed>"
    create_date:     "<computed>"
    name:            "masters.dev.k8s.orovecchia.com"
    path:            "/"
    roles.#:         "1"
    roles.241661314: "masters.dev.k8s.orovecchia.com"
    unique_id:       "<computed>"

+ aws_iam_instance_profile.nodes-dev-k8s-orovecchia-com
    arn:             "<computed>"
    create_date:     "<computed>"
    name:            "nodes.dev.k8s.orovecchia.com"
    path:            "/"
    roles.#:         "1"
    roles.241378590: "nodes.dev.k8s.orovecchia.com"
    unique_id:       "<computed>"

+ aws_iam_role.masters-dev-k8s-orovecchia-com
    arn:                "<computed>"
    assume_role_policy: "{\n  \"Version\": \"2012-10-17\",\n  \"Statement\": [\n    {\n      \"Effect\": \"Allow\",\n      \"Principal\": { \"Service\": \"ec2.amazonaws.com\"},\n      \"Action\": \"sts:AssumeRole\"\n    }\n  ]\n}\n"
    name:               "masters.dev.k8s.orovecchia.com"
    path:               "/"
    unique_id:          "<computed>"

+ aws_iam_role.nodes-dev-k8s-orovecchia-com
    arn:                "<computed>"
    assume_role_policy: "{\n  \"Version\": \"2012-10-17\",\n  \"Statement\": [\n    {\n      \"Effect\": \"Allow\",\n      \"Principal\": { \"Service\": \"ec2.amazonaws.com\"},\n      \"Action\": \"sts:AssumeRole\"\n    }\n  ]\n}\n"
    name:               "nodes.dev.k8s.orovecchia.com"
    path:               "/"
    unique_id:          "<computed>"

+ aws_iam_role_policy.masters-dev-k8s-orovecchia-com
    name:   "masters.dev.k8s.orovecchia.com"
    policy: "{\n  \"Version\": \"2012-10-17\",\n  \"Statement\": [\n    {\n      \"Effect\": \"Allow\",\n      \"Action\": [\n        \"ecr:GetAuthorizationToken\",\n        \"ecr:BatchCheckLayerAvailability\",\n        \"ecr:GetDownloadUrlForLayer\",\n        \"ecr:GetRepositoryPolicy\",\n        \"ecr:DescribeRepositories\",\n        \"ecr:ListImages\",\n        \"ecr:BatchGetImage\"\n      ],\n      \"Resource\": [\n        \"*\"\n      ]\n    },\n    {\n      \"Effect\": \"Allow\",\n      \"Action\": [\n        \"ec2:*\"\n      ],\n      \"Resource\": [\n        \"*\"\n      ]\n    },\n    {\n      \"Effect\": \"Allow\",\n      \"Action\": [\n        \"route53:*\"\n      ],\n      \"Resource\": [\n        \"*\"\n      ]\n    },\n    {\n      \"Effect\": \"Allow\",\n      \"Action\": [\n        \"elasticloadbalancing:*\"\n      ],\n      \"Resource\": [\n        \"*\"\n      ]\n    },\n    {\n      \"Effect\": \"Allow\",\n      \"Action\": [\n        \"s3:*\"\n      ],\n      \"Resource\": [\n        \"arn:aws:s3:::oro-kops-state/dev.k8s.orovecchia.com\",\n        \"arn:aws:s3:::oro-kops-state/dev.k8s.orovecchia.com/*\"\n      ]\n    },\n    {\n      \"Effect\": \"Allow\",\n      \"Action\": [\n        \"s3:GetBucketLocation\",\n        \"s3:ListBucket\"\n      ],\n      \"Resource\": [\n        \"arn:aws:s3:::oro-kops-state\"\n      ]\n    }\n  ]\n}"
    role:   "masters.dev.k8s.orovecchia.com"

+ aws_iam_role_policy.nodes-dev-k8s-orovecchia-com
    name:   "nodes.dev.k8s.orovecchia.com"
    policy: "{\n  \"Version\": \"2012-10-17\",\n  \"Statement\": [\n    {\n      \"Effect\": \"Allow\",\n      \"Action\": [\n        \"ec2:Describe*\"\n      ],\n      \"Resource\": [\n        \"*\"\n      ]\n    },\n    {\n      \"Effect\": \"Allow\",\n      \"Action\": [\n        \"route53:*\"\n      ],\n      \"Resource\": [\n        \"*\"\n      ]\n    },\n    {\n      \"Effect\": \"Allow\",\n      \"Action\": [\n        \"ecr:GetAuthorizationToken\",\n        \"ecr:BatchCheckLayerAvailability\",\n        \"ecr:GetDownloadUrlForLayer\",\n        \"ecr:GetRepositoryPolicy\",\n        \"ecr:DescribeRepositories\",\n        \"ecr:ListImages\",\n        \"ecr:BatchGetImage\"\n      ],\n      \"Resource\": [\n        \"*\"\n      ]\n    },\n    {\n      \"Effect\": \"Allow\",\n      \"Action\": [\n        \"s3:*\"\n      ],\n      \"Resource\": [\n        \"arn:aws:s3:::oro-kops-state/dev.k8s.orovecchia.com\",\n        \"arn:aws:s3:::oro-kops-state/dev.k8s.orovecchia.com/*\"\n      ]\n    },\n    {\n      \"Effect\": \"Allow\",\n      \"Action\": [\n        \"s3:GetBucketLocation\",\n        \"s3:ListBucket\"\n      ],\n      \"Resource\": [\n        \"arn:aws:s3:::oro-kops-state\"\n      ]\n    }\n  ]\n}"
    role:   "nodes.dev.k8s.orovecchia.com"

+ aws_internet_gateway.dev-k8s-orovecchia-com
    tags.%:                 "2"
    tags.KubernetesCluster: "dev.k8s.orovecchia.com"
    tags.Name:              "dev.k8s.orovecchia.com"
    vpc_id:                 "${aws_vpc.dev-k8s-orovecchia-com.id}"

+ aws_key_pair.kubernetes-dev-k8s-orovecchia-com-952344bf29bc219a86d3bc12f1767073
    fingerprint: "<computed>"
    key_name:    "kubernetes.dev.k8s.orovecchia.com-95:23:44:bf:29:bc:21:9a:86:d3:bc:12:f1:76:70:73"
    public_key:  "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7HZmYWG4yWSRCN2bd25Ex0vDE2406sQH6b3QAaQUsx9l4sMnMG6iL0FXCwKqeizthua1sxri+ZAqrWlVhv5vGG7gYs5ua7gAdV3I9auuUiKUb+viDXq8CfERWevqDypYTUl/5y4ujFRGnWQR0hbaL6L/q9CdtnMjduESE7Lwjr91nkYnSGOgLde5tEEKbrHItFEg8yhYOGYmJUthsIcm075/0L/v6w/mDActGg+8GTDJDUyjHgaEtrob09/AJQ+gEpj6/98ZhtPUsB4KKwyONAZb4cUj6HljdYl2DNwsvpibkH7/pBIE82LPkt9t+PfFbKthj8EI/pKhPO28AkFEN orm@automic.com"

+ aws_launch_configuration.master-us-east-1a-masters-dev-k8s-orovecchia-com
    associate_public_ip_address:                    "true"
    ebs_block_device.#:                             "<computed>"
    ebs_optimized:                                  "<computed>"
    enable_monitoring:                              "true"
    ephemeral_block_device.#:                       "1"
    ephemeral_block_device.3292514005.device_name:  "/dev/sdc"
    ephemeral_block_device.3292514005.virtual_name: "ephemeral0"
    iam_instance_profile:                           "${aws_iam_instance_profile.masters-dev-k8s-orovecchia-com.id}"
    image_id:                                       "ami-08ee2f65"
    instance_type:                                  "m3.large"
    key_name:                                       "${aws_key_pair.kubernetes-dev-k8s-orovecchia-com-952344bf29bc219a86d3bc12f1767073.id}"
    name:                                           "<computed>"
    name_prefix:                                    "master-us-east-1a.masters.dev.k8s.orovecchia.com-"
    root_block_device.#:                            "1"
    root_block_device.0.delete_on_termination:      "true"
    root_block_device.0.iops:                       "<computed>"
    root_block_device.0.volume_size:                "20"
    root_block_device.0.volume_type:                "gp2"
    security_groups.#:                              "<computed>"
    user_data:                                      "e2e7c9f61a9d6ff7aba8961fb9539217b262dfd2"

+ aws_launch_configuration.nodes-dev-k8s-orovecchia-com
    associate_public_ip_address:               "true"
    ebs_block_device.#:                        "<computed>"
    ebs_optimized:                             "<computed>"
    enable_monitoring:                         "true"
    iam_instance_profile:                      "${aws_iam_instance_profile.nodes-dev-k8s-orovecchia-com.id}"
    image_id:                                  "ami-08ee2f65"
    instance_type:                             "t2.medium"
    key_name:                                  "${aws_key_pair.kubernetes-dev-k8s-orovecchia-com-952344bf29bc219a86d3bc12f1767073.id}"
    name:                                      "<computed>"
    name_prefix:                               "nodes.dev.k8s.orovecchia.com-"
    root_block_device.#:                       "1"
    root_block_device.0.delete_on_termination: "true"
    root_block_device.0.iops:                  "<computed>"
    root_block_device.0.volume_size:           "20"
    root_block_device.0.volume_type:           "gp2"
    security_groups.#:                         "<computed>"
    user_data:                                 "2922481b3a0debb2260e4be5b59ae24d31416939"

+ aws_route.0-0-0-0--0
    destination_cidr_block:     "0.0.0.0/0"
    destination_prefix_list_id: "<computed>"
    gateway_id:                 "${aws_internet_gateway.dev-k8s-orovecchia-com.id}"
    instance_id:                "<computed>"
    instance_owner_id:          "<computed>"
    nat_gateway_id:             "<computed>"
    network_interface_id:       "<computed>"
    origin:                     "<computed>"
    route_table_id:             "${aws_route_table.dev-k8s-orovecchia-com.id}"
    state:                      "<computed>"

+ aws_route_table.dev-k8s-orovecchia-com
    route.#:                "<computed>"
    tags.%:                 "2"
    tags.KubernetesCluster: "dev.k8s.orovecchia.com"
    tags.Name:              "dev.k8s.orovecchia.com"
    vpc_id:                 "${aws_vpc.dev-k8s-orovecchia-com.id}"

+ aws_route_table_association.us-east-1a-dev-k8s-orovecchia-com
    route_table_id: "${aws_route_table.dev-k8s-orovecchia-com.id}"
    subnet_id:      "${aws_subnet.us-east-1a-dev-k8s-orovecchia-com.id}"

+ aws_security_group.masters-dev-k8s-orovecchia-com
    description:            "Security group for masters"
    egress.#:               "<computed>"
    ingress.#:              "<computed>"
    name:                   "masters.dev.k8s.orovecchia.com"
    owner_id:               "<computed>"
    tags.%:                 "2"
    tags.KubernetesCluster: "dev.k8s.orovecchia.com"
    tags.Name:              "masters.dev.k8s.orovecchia.com"
    vpc_id:                 "${aws_vpc.dev-k8s-orovecchia-com.id}"

+ aws_security_group.nodes-dev-k8s-orovecchia-com
    description:            "Security group for nodes"
    egress.#:               "<computed>"
    ingress.#:              "<computed>"
    name:                   "nodes.dev.k8s.orovecchia.com"
    owner_id:               "<computed>"
    tags.%:                 "2"
    tags.KubernetesCluster: "dev.k8s.orovecchia.com"
    tags.Name:              "nodes.dev.k8s.orovecchia.com"
    vpc_id:                 "${aws_vpc.dev-k8s-orovecchia-com.id}"

+ aws_security_group_rule.all-master-to-master
    from_port:                "0"
    protocol:                 "-1"
    security_group_id:        "${aws_security_group.masters-dev-k8s-orovecchia-com.id}"
    self:                     "false"
    source_security_group_id: "${aws_security_group.masters-dev-k8s-orovecchia-com.id}"
    to_port:                  "0"
    type:                     "ingress"

+ aws_security_group_rule.all-master-to-node
    from_port:                "0"
    protocol:                 "-1"
    security_group_id:        "${aws_security_group.nodes-dev-k8s-orovecchia-com.id}"
    self:                     "false"
    source_security_group_id: "${aws_security_group.masters-dev-k8s-orovecchia-com.id}"
    to_port:                  "0"
    type:                     "ingress"

+ aws_security_group_rule.all-node-to-master
    from_port:                "0"
    protocol:                 "-1"
    security_group_id:        "${aws_security_group.masters-dev-k8s-orovecchia-com.id}"
    self:                     "false"
    source_security_group_id: "${aws_security_group.nodes-dev-k8s-orovecchia-com.id}"
    to_port:                  "0"
    type:                     "ingress"

+ aws_security_group_rule.all-node-to-node
    from_port:                "0"
    protocol:                 "-1"
    security_group_id:        "${aws_security_group.nodes-dev-k8s-orovecchia-com.id}"
    self:                     "false"
    source_security_group_id: "${aws_security_group.nodes-dev-k8s-orovecchia-com.id}"
    to_port:                  "0"
    type:                     "ingress"

+ aws_security_group_rule.https-external-to-master
    cidr_blocks.#:            "1"
    cidr_blocks.0:            "0.0.0.0/0"
    from_port:                "443"
    protocol:                 "tcp"
    security_group_id:        "${aws_security_group.masters-dev-k8s-orovecchia-com.id}"
    self:                     "false"
    source_security_group_id: "<computed>"
    to_port:                  "443"
    type:                     "ingress"

+ aws_security_group_rule.master-egress
    cidr_blocks.#:            "1"
    cidr_blocks.0:            "0.0.0.0/0"
    from_port:                "0"
    protocol:                 "-1"
    security_group_id:        "${aws_security_group.masters-dev-k8s-orovecchia-com.id}"
    self:                     "false"
    source_security_group_id: "<computed>"
    to_port:                  "0"
    type:                     "egress"

+ aws_security_group_rule.node-egress
    cidr_blocks.#:            "1"
    cidr_blocks.0:            "0.0.0.0/0"
    from_port:                "0"
    protocol:                 "-1"
    security_group_id:        "${aws_security_group.nodes-dev-k8s-orovecchia-com.id}"
    self:                     "false"
    source_security_group_id: "<computed>"
    to_port:                  "0"
    type:                     "egress"

+ aws_security_group_rule.ssh-external-to-master
    cidr_blocks.#:            "1"
    cidr_blocks.0:            "0.0.0.0/0"
    from_port:                "22"
    protocol:                 "tcp"
    security_group_id:        "${aws_security_group.masters-dev-k8s-orovecchia-com.id}"
    self:                     "false"
    source_security_group_id: "<computed>"
    to_port:                  "22"
    type:                     "ingress"

+ aws_security_group_rule.ssh-external-to-node
    cidr_blocks.#:            "1"
    cidr_blocks.0:            "0.0.0.0/0"
    from_port:                "22"
    protocol:                 "tcp"
    security_group_id:        "${aws_security_group.nodes-dev-k8s-orovecchia-com.id}"
    self:                     "false"
    source_security_group_id: "<computed>"
    to_port:                  "22"
    type:                     "ingress"

+ aws_subnet.us-east-1a-dev-k8s-orovecchia-com
    availability_zone:       "us-east-1a"
    cidr_block:              "172.20.32.0/19"
    map_public_ip_on_launch: "false"
    tags.%:                  "2"
    tags.KubernetesCluster:  "dev.k8s.orovecchia.com"
    tags.Name:               "us-east-1a.dev.k8s.orovecchia.com"
    vpc_id:                  "${aws_vpc.dev-k8s-orovecchia-com.id}"

+ aws_vpc.dev-k8s-orovecchia-com
    cidr_block:                "172.20.0.0/16"
    default_network_acl_id:    "<computed>"
    default_route_table_id:    "<computed>"
    default_security_group_id: "<computed>"
    dhcp_options_id:           "<computed>"
    enable_classiclink:        "<computed>"
    enable_dns_hostnames:      "true"
    enable_dns_support:        "true"
    instance_tenancy:          "<computed>"
    main_route_table_id:       "<computed>"
    tags.%:                    "2"
    tags.KubernetesCluster:    "dev.k8s.orovecchia.com"
    tags.Name:                 "dev.k8s.orovecchia.com"

+ aws_vpc_dhcp_options.dev-k8s-orovecchia-com
    domain_name:            "ec2.internal"
    domain_name_servers.#:  "1"
    domain_name_servers.0:  "AmazonProvidedDNS"
    tags.%:                 "2"
    tags.KubernetesCluster: "dev.k8s.orovecchia.com"
    tags.Name:              "dev.k8s.orovecchia.com"

+ aws_vpc_dhcp_options_association.dev-k8s-orovecchia-com
    dhcp_options_id: "${aws_vpc_dhcp_options.dev-k8s-orovecchia-com.id}"
    vpc_id:          "${aws_vpc.dev-k8s-orovecchia-com.id}"


Plan: 32 to add, 0 to change, 0 to destroy.
```

``` bash
terraform apply
```

``` example
aws_key_pair.kubernetes-dev-k8s-orovecchia-com-952344bf29bc219a86d3bc12f1767073: Creating...
  fingerprint: "" => "<computed>"
  key_name:    "" => "kubernetes.dev.k8s.orovecchia.com-95:23:44:bf:29:bc:21:9a:86:d3:bc:12:f1:76:70:73"
  public_key:  "" => "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7HZmYWG4yWSRCN2bd25Ex0vDE2406sQH6b3QAaQUsx9l4sMnMG6iL0FXCwKqeizthua1sxri+ZAqrWlVhv5vGG7gYs5ua7gAdV3I9auuUiKUb+viDXq8CfERWevqDypYTUl/5y4ujFRGnWQR0hbaL6L/q9CdtnMjduESE7Lwjr91nkYnSGOgLde5tEEKbrHItFEg8yhYOGYmJUthsIcm075/0L/v6w/mDActGg+8GTDJDUyjHgaEtrob09/AJQ+gEpj6/98ZhtPUsB4KKwyONAZb4cUj6HljdYl2DNwsvpibkH7/pBIE82LPkt9t+PfFbKthj8EI/pKhPO28AkFEN orm@automic.com"
aws_iam_role.masters-dev-k8s-orovecchia-com: Creating...
  arn:                "" => "<computed>"
  assume_role_policy: "" => "{\n  \"Version\": \"2012-10-17\",\n  \"Statement\": [\n    {\n      \"Effect\": \"Allow\",\n      \"Principal\": { \"Service\": \"ec2.amazonaws.com\"},\n      \"Action\": \"sts:AssumeRole\"\n    }\n  ]\n}\n"
  name:               "" => "masters.dev.k8s.orovecchia.com"
  path:               "" => "/"
  unique_id:          "" => "<computed>"
aws_vpc_dhcp_options.dev-k8s-orovecchia-com: Creating...
  domain_name:            "" => "ec2.internal"
  domain_name_servers.#:  "" => "1"
  domain_name_servers.0:  "" => "AmazonProvidedDNS"
  tags.%:                 "" => "2"
  tags.KubernetesCluster: "" => "dev.k8s.orovecchia.com"
  tags.Name:              "" => "dev.k8s.orovecchia.com"
aws_iam_role.nodes-dev-k8s-orovecchia-com: Creating...
  arn:                "" => "<computed>"
  assume_role_policy: "" => "{\n  \"Version\": \"2012-10-17\",\n  \"Statement\": [\n    {\n      \"Effect\": \"Allow\",\n      \"Principal\": { \"Service\": \"ec2.amazonaws.com\"},\n      \"Action\": \"sts:AssumeRole\"\n    }\n  ]\n}\n"
  name:               "" => "nodes.dev.k8s.orovecchia.com"
  path:               "" => "/"
  unique_id:          "" => "<computed>"
aws_vpc.dev-k8s-orovecchia-com: Creating...
  cidr_block:                "" => "172.20.0.0/16"
  default_network_acl_id:    "" => "<computed>"
  default_route_table_id:    "" => "<computed>"
  default_security_group_id: "" => "<computed>"
  dhcp_options_id:           "" => "<computed>"
  enable_classiclink:        "" => "<computed>"
  enable_dns_hostnames:      "" => "true"
  enable_dns_support:        "" => "true"
  instance_tenancy:          "" => "<computed>"
  main_route_table_id:       "" => "<computed>"
  tags.%:                    "" => "2"
  tags.KubernetesCluster:    "" => "dev.k8s.orovecchia.com"
  tags.Name:                 "" => "dev.k8s.orovecchia.com"
aws_ebs_volume.us-east-1a-etcd-events-dev-k8s-orovecchia-com: Creating...
  availability_zone:       "" => "us-east-1a"
  encrypted:               "" => "false"
  iops:                    "" => "<computed>"
  kms_key_id:              "" => "<computed>"
  size:                    "" => "20"
  snapshot_id:             "" => "<computed>"
  tags.%:                  "" => "4"
  tags.KubernetesCluster:  "" => "dev.k8s.orovecchia.com"
  tags.Name:               "" => "us-east-1a.etcd-events.dev.k8s.orovecchia.com"
  tags.k8s.io/etcd/events: "" => "us-east-1a/us-east-1a"
  tags.k8s.io/role/master: "" => "1"
  type:                    "" => "gp2"
aws_ebs_volume.us-east-1a-etcd-main-dev-k8s-orovecchia-com: Creating...
  availability_zone:       "" => "us-east-1a"
  encrypted:               "" => "false"
  iops:                    "" => "<computed>"
  kms_key_id:              "" => "<computed>"
  size:                    "" => "20"
  snapshot_id:             "" => "<computed>"
  tags.%:                  "" => "4"
  tags.KubernetesCluster:  "" => "dev.k8s.orovecchia.com"
  tags.Name:               "" => "us-east-1a.etcd-main.dev.k8s.orovecchia.com"
  tags.k8s.io/etcd/main:   "" => "us-east-1a/us-east-1a"
  tags.k8s.io/role/master: "" => "1"
  type:                    "" => "gp2"
aws_key_pair.kubernetes-dev-k8s-orovecchia-com-952344bf29bc219a86d3bc12f1767073: Creation complete
aws_iam_role.nodes-dev-k8s-orovecchia-com: Creation complete
aws_iam_role_policy.nodes-dev-k8s-orovecchia-com: Creating...
  name:   "" => "nodes.dev.k8s.orovecchia.com"
  policy: "" => "{\n  \"Version\": \"2012-10-17\",\n  \"Statement\": [\n    {\n      \"Effect\": \"Allow\",\n      \"Action\": [\n        \"ec2:Describe*\"\n      ],\n      \"Resource\": [\n        \"*\"\n      ]\n    },\n    {\n      \"Effect\": \"Allow\",\n      \"Action\": [\n        \"route53:*\"\n      ],\n      \"Resource\": [\n        \"*\"\n      ]\n    },\n    {\n      \"Effect\": \"Allow\",\n      \"Action\": [\n        \"ecr:GetAuthorizationToken\",\n        \"ecr:BatchCheckLayerAvailability\",\n        \"ecr:GetDownloadUrlForLayer\",\n        \"ecr:GetRepositoryPolicy\",\n        \"ecr:DescribeRepositories\",\n        \"ecr:ListImages\",\n        \"ecr:BatchGetImage\"\n      ],\n      \"Resource\": [\n        \"*\"\n      ]\n    },\n    {\n      \"Effect\": \"Allow\",\n      \"Action\": [\n        \"s3:*\"\n      ],\n      \"Resource\": [\n        \"arn:aws:s3:::oro-kops-state/dev.k8s.orovecchia.com\",\n        \"arn:aws:s3:::oro-kops-state/dev.k8s.orovecchia.com/*\"\n      ]\n    },\n    {\n      \"Effect\": \"Allow\",\n      \"Action\": [\n        \"s3:GetBucketLocation\",\n        \"s3:ListBucket\"\n      ],\n      \"Resource\": [\n        \"arn:aws:s3:::oro-kops-state\"\n      ]\n    }\n  ]\n}"
  role:   "" => "nodes.dev.k8s.orovecchia.com"
aws_iam_instance_profile.nodes-dev-k8s-orovecchia-com: Creating...
  arn:             "" => "<computed>"
  create_date:     "" => "<computed>"
  name:            "" => "nodes.dev.k8s.orovecchia.com"
  path:            "" => "/"
  roles.#:         "" => "1"
  roles.241378590: "" => "nodes.dev.k8s.orovecchia.com"
  unique_id:       "" => "<computed>"
aws_iam_role.masters-dev-k8s-orovecchia-com: Creation complete
aws_iam_role_policy.masters-dev-k8s-orovecchia-com: Creating...
  name:   "" => "masters.dev.k8s.orovecchia.com"
  policy: "" => "{\n  \"Version\": \"2012-10-17\",\n  \"Statement\": [\n    {\n      \"Effect\": \"Allow\",\n      \"Action\": [\n        \"ecr:GetAuthorizationToken\",\n        \"ecr:BatchCheckLayerAvailability\",\n        \"ecr:GetDownloadUrlForLayer\",\n        \"ecr:GetRepositoryPolicy\",\n        \"ecr:DescribeRepositories\",\n        \"ecr:ListImages\",\n        \"ecr:BatchGetImage\"\n      ],\n      \"Resource\": [\n        \"*\"\n      ]\n    },\n    {\n      \"Effect\": \"Allow\",\n      \"Action\": [\n        \"ec2:*\"\n      ],\n      \"Resource\": [\n        \"*\"\n      ]\n    },\n    {\n      \"Effect\": \"Allow\",\n      \"Action\": [\n        \"route53:*\"\n      ],\n      \"Resource\": [\n        \"*\"\n      ]\n    },\n    {\n      \"Effect\": \"Allow\",\n      \"Action\": [\n        \"elasticloadbalancing:*\"\n      ],\n      \"Resource\": [\n        \"*\"\n      ]\n    },\n    {\n      \"Effect\": \"Allow\",\n      \"Action\": [\n        \"s3:*\"\n      ],\n      \"Resource\": [\n        \"arn:aws:s3:::oro-kops-state/dev.k8s.orovecchia.com\",\n        \"arn:aws:s3:::oro-kops-state/dev.k8s.orovecchia.com/*\"\n      ]\n    },\n    {\n      \"Effect\": \"Allow\",\n      \"Action\": [\n        \"s3:GetBucketLocation\",\n        \"s3:ListBucket\"\n      ],\n      \"Resource\": [\n        \"arn:aws:s3:::oro-kops-state\"\n      ]\n    }\n  ]\n}"
  role:   "" => "masters.dev.k8s.orovecchia.com"
aws_iam_instance_profile.masters-dev-k8s-orovecchia-com: Creating...
  arn:             "" => "<computed>"
  create_date:     "" => "<computed>"
  name:            "" => "masters.dev.k8s.orovecchia.com"
  path:            "" => "/"
  roles.#:         "" => "1"
  roles.241661314: "" => "masters.dev.k8s.orovecchia.com"
  unique_id:       "" => "<computed>"
aws_iam_role_policy.nodes-dev-k8s-orovecchia-com: Creation complete
aws_iam_role_policy.masters-dev-k8s-orovecchia-com: Creation complete
aws_iam_instance_profile.nodes-dev-k8s-orovecchia-com: Creation complete
aws_iam_instance_profile.masters-dev-k8s-orovecchia-com: Creation complete
aws_vpc_dhcp_options.dev-k8s-orovecchia-com: Creation complete
aws_vpc.dev-k8s-orovecchia-com: Creation complete
aws_vpc_dhcp_options_association.dev-k8s-orovecchia-com: Creating...
  dhcp_options_id: "" => "dopt-023f6d66"
  vpc_id:          "" => "vpc-7821081f"
aws_internet_gateway.dev-k8s-orovecchia-com: Creating...
  tags.%:                 "0" => "2"
  tags.KubernetesCluster: "" => "dev.k8s.orovecchia.com"
  tags.Name:              "" => "dev.k8s.orovecchia.com"
  vpc_id:                 "" => "vpc-7821081f"
aws_subnet.us-east-1a-dev-k8s-orovecchia-com: Creating...
  availability_zone:       "" => "us-east-1a"
  cidr_block:              "" => "172.20.32.0/19"
  map_public_ip_on_launch: "" => "false"
  tags.%:                  "" => "2"
  tags.KubernetesCluster:  "" => "dev.k8s.orovecchia.com"
  tags.Name:               "" => "us-east-1a.dev.k8s.orovecchia.com"
  vpc_id:                  "" => "vpc-7821081f"
aws_route_table.dev-k8s-orovecchia-com: Creating...
  route.#:                "" => "<computed>"
  tags.%:                 "" => "2"
  tags.KubernetesCluster: "" => "dev.k8s.orovecchia.com"
  tags.Name:              "" => "dev.k8s.orovecchia.com"
  vpc_id:                 "" => "vpc-7821081f"
aws_security_group.masters-dev-k8s-orovecchia-com: Creating...
  description:            "" => "Security group for masters"
  egress.#:               "" => "<computed>"
  ingress.#:              "" => "<computed>"
  name:                   "" => "masters.dev.k8s.orovecchia.com"
  owner_id:               "" => "<computed>"
  tags.%:                 "" => "2"
  tags.KubernetesCluster: "" => "dev.k8s.orovecchia.com"
  tags.Name:              "" => "masters.dev.k8s.orovecchia.com"
  vpc_id:                 "" => "vpc-7821081f"
aws_security_group.nodes-dev-k8s-orovecchia-com: Creating...
  description:            "" => "Security group for nodes"
  egress.#:               "" => "<computed>"
  ingress.#:              "" => "<computed>"
  name:                   "" => "nodes.dev.k8s.orovecchia.com"
  owner_id:               "" => "<computed>"
  tags.%:                 "" => "2"
  tags.KubernetesCluster: "" => "dev.k8s.orovecchia.com"
  tags.Name:              "" => "nodes.dev.k8s.orovecchia.com"
  vpc_id:                 "" => "vpc-7821081f"
aws_ebs_volume.us-east-1a-etcd-main-dev-k8s-orovecchia-com: Still creating... (10s elapsed)
aws_ebs_volume.us-east-1a-etcd-events-dev-k8s-orovecchia-com: Still creating... (10s elapsed)
aws_vpc_dhcp_options_association.dev-k8s-orovecchia-com: Creation complete
aws_ebs_volume.us-east-1a-etcd-events-dev-k8s-orovecchia-com: Creation complete
aws_subnet.us-east-1a-dev-k8s-orovecchia-com: Creation complete
aws_route_table.dev-k8s-orovecchia-com: Creation complete
aws_route_table_association.us-east-1a-dev-k8s-orovecchia-com: Creating...
  route_table_id: "" => "rtb-6cd35a0a"
  subnet_id:      "" => "subnet-9f43bec4"
aws_ebs_volume.us-east-1a-etcd-main-dev-k8s-orovecchia-com: Creation complete
aws_internet_gateway.dev-k8s-orovecchia-com: Creation complete
aws_route_table_association.us-east-1a-dev-k8s-orovecchia-com: Creation complete
aws_route.0-0-0-0--0: Creating...
  destination_cidr_block:     "" => "0.0.0.0/0"
  destination_prefix_list_id: "" => "<computed>"
  gateway_id:                 "" => "igw-dbf906bc"
  instance_id:                "" => "<computed>"
  instance_owner_id:          "" => "<computed>"
  nat_gateway_id:             "" => "<computed>"
  network_interface_id:       "" => "<computed>"
  origin:                     "" => "<computed>"
  route_table_id:             "" => "rtb-6cd35a0a"
  state:                      "" => "<computed>"
aws_security_group.masters-dev-k8s-orovecchia-com: Creation complete
aws_security_group_rule.https-external-to-master: Creating...
  cidr_blocks.#:            "" => "1"
  cidr_blocks.0:            "" => "0.0.0.0/0"
  from_port:                "" => "443"
  protocol:                 "" => "tcp"
  security_group_id:        "" => "sg-e17d289b"
  self:                     "" => "false"
  source_security_group_id: "" => "<computed>"
  to_port:                  "" => "443"
  type:                     "" => "ingress"
aws_security_group_rule.all-master-to-master: Creating...
  from_port:                "" => "0"
  protocol:                 "" => "-1"
  security_group_id:        "" => "sg-e17d289b"
  self:                     "" => "false"
  source_security_group_id: "" => "sg-e17d289b"
  to_port:                  "" => "0"
  type:                     "" => "ingress"
aws_security_group_rule.ssh-external-to-master: Creating...
  cidr_blocks.#:            "" => "1"
  cidr_blocks.0:            "" => "0.0.0.0/0"
  from_port:                "" => "22"
  protocol:                 "" => "tcp"
  security_group_id:        "" => "sg-e17d289b"
  self:                     "" => "false"
  source_security_group_id: "" => "<computed>"
  to_port:                  "" => "22"
  type:                     "" => "ingress"
aws_security_group_rule.master-egress: Creating...
  cidr_blocks.#:            "" => "1"
  cidr_blocks.0:            "" => "0.0.0.0/0"
  from_port:                "" => "0"
  protocol:                 "" => "-1"
  security_group_id:        "" => "sg-e17d289b"
  self:                     "" => "false"
  source_security_group_id: "" => "<computed>"
  to_port:                  "" => "0"
  type:                     "" => "egress"
aws_launch_configuration.master-us-east-1a-masters-dev-k8s-orovecchia-com: Creating...
  associate_public_ip_address:                    "" => "true"
  ebs_block_device.#:                             "" => "<computed>"
  ebs_optimized:                                  "" => "<computed>"
  enable_monitoring:                              "" => "true"
  ephemeral_block_device.#:                       "" => "1"
  ephemeral_block_device.3292514005.device_name:  "" => "/dev/sdc"
  ephemeral_block_device.3292514005.virtual_name: "" => "ephemeral0"
  iam_instance_profile:                           "" => "masters.dev.k8s.orovecchia.com"
  image_id:                                       "" => "ami-08ee2f65"
  instance_type:                                  "" => "m3.large"
  key_name:                                       "" => "kubernetes.dev.k8s.orovecchia.com-95:23:44:bf:29:bc:21:9a:86:d3:bc:12:f1:76:70:73"
  name:                                           "" => "<computed>"
  name_prefix:                                    "" => "master-us-east-1a.masters.dev.k8s.orovecchia.com-"
  root_block_device.#:                            "" => "1"
  root_block_device.0.delete_on_termination:      "" => "true"
  root_block_device.0.iops:                       "" => "<computed>"
  root_block_device.0.volume_size:                "" => "20"
  root_block_device.0.volume_type:                "" => "gp2"
  security_groups.#:                              "" => "1"
  security_groups.1920077966:                     "" => "sg-e17d289b"
  user_data:                                      "" => "e2e7c9f61a9d6ff7aba8961fb9539217b262dfd2"
aws_security_group.nodes-dev-k8s-orovecchia-com: Creation complete
aws_security_group_rule.all-node-to-node: Creating...
  from_port:                "" => "0"
  protocol:                 "" => "-1"
  security_group_id:        "" => "sg-e67d289c"
  self:                     "" => "false"
  source_security_group_id: "" => "sg-e67d289c"
  to_port:                  "" => "0"
  type:                     "" => "ingress"
aws_security_group_rule.all-master-to-node: Creating...
  from_port:                "" => "0"
  protocol:                 "" => "-1"
  security_group_id:        "" => "sg-e67d289c"
  self:                     "" => "false"
  source_security_group_id: "" => "sg-e17d289b"
  to_port:                  "" => "0"
  type:                     "" => "ingress"
aws_security_group_rule.all-node-to-master: Creating...
  from_port:                "" => "0"
  protocol:                 "" => "-1"
  security_group_id:        "" => "sg-e17d289b"
  self:                     "" => "false"
  source_security_group_id: "" => "sg-e67d289c"
  to_port:                  "" => "0"
  type:                     "" => "ingress"
aws_security_group_rule.ssh-external-to-node: Creating...
  cidr_blocks.#:            "" => "1"
  cidr_blocks.0:            "" => "0.0.0.0/0"
  from_port:                "" => "22"
  protocol:                 "" => "tcp"
  security_group_id:        "" => "sg-e67d289c"
  self:                     "" => "false"
  source_security_group_id: "" => "<computed>"
  to_port:                  "" => "22"
  type:                     "" => "ingress"
aws_route.0-0-0-0--0: Creation complete
aws_security_group_rule.node-egress: Creating...
  cidr_blocks.#:            "" => "1"
  cidr_blocks.0:            "" => "0.0.0.0/0"
  from_port:                "" => "0"
  protocol:                 "" => "-1"
  security_group_id:        "" => "sg-e67d289c"
  self:                     "" => "false"
  source_security_group_id: "" => "<computed>"
  to_port:                  "" => "0"
  type:                     "" => "egress"
aws_security_group_rule.https-external-to-master: Creation complete
aws_launch_configuration.nodes-dev-k8s-orovecchia-com: Creating...
  associate_public_ip_address:               "" => "true"
  ebs_block_device.#:                        "" => "<computed>"
  ebs_optimized:                             "" => "<computed>"
  enable_monitoring:                         "" => "true"
  iam_instance_profile:                      "" => "nodes.dev.k8s.orovecchia.com"
  image_id:                                  "" => "ami-08ee2f65"
  instance_type:                             "" => "t2.medium"
  key_name:                                  "" => "kubernetes.dev.k8s.orovecchia.com-95:23:44:bf:29:bc:21:9a:86:d3:bc:12:f1:76:70:73"
  name:                                      "" => "<computed>"
  name_prefix:                               "" => "nodes.dev.k8s.orovecchia.com-"
  root_block_device.#:                       "" => "1"
  root_block_device.0.delete_on_termination: "" => "true"
  root_block_device.0.iops:                  "" => "<computed>"
  root_block_device.0.volume_size:           "" => "20"
  root_block_device.0.volume_type:           "" => "gp2"
  security_groups.#:                         "" => "1"
  security_groups.3234995862:                "" => "sg-e67d289c"
  user_data:                                 "" => "2922481b3a0debb2260e4be5b59ae24d31416939"
aws_security_group_rule.all-node-to-node: Creation complete
aws_launch_configuration.master-us-east-1a-masters-dev-k8s-orovecchia-com: Creation complete
aws_autoscaling_group.master-us-east-1a-masters-dev-k8s-orovecchia-com: Creating...
  arn:                                "" => "<computed>"
  availability_zones.#:               "" => "<computed>"
  default_cooldown:                   "" => "<computed>"
  desired_capacity:                   "" => "<computed>"
  force_delete:                       "" => "false"
  health_check_grace_period:          "" => "300"
  health_check_type:                  "" => "<computed>"
  launch_configuration:               "" => "master-us-east-1a.masters.dev.k8s.orovecchia.com-201609282006304731484157ff"
  max_size:                           "" => "1"
  metrics_granularity:                "" => "1Minute"
  min_size:                           "" => "1"
  name:                               "" => "master-us-east-1a.masters.dev.k8s.orovecchia.com"
  protect_from_scale_in:              "" => "false"
  tag.#:                              "" => "5"
  tag.1033606357.key:                 "" => "k8s.io/dns/internal"
  tag.1033606357.propagate_at_launch: "" => "true"
  tag.1033606357.value:               "" => "api.internal.dev.k8s.orovecchia.com"
  tag.1601041186.key:                 "" => "k8s.io/role/master"
  tag.1601041186.propagate_at_launch: "" => "true"
  tag.1601041186.value:               "" => "1"
  tag.2531097064.key:                 "" => "k8s.io/dns/public"
  tag.2531097064.propagate_at_launch: "" => "true"
  tag.2531097064.value:               "" => "api.dev.k8s.orovecchia.com"
  tag.453089870.key:                  "" => "Name"
  tag.453089870.propagate_at_launch:  "" => "true"
  tag.453089870.value:                "" => "master-us-east-1a.masters.dev.k8s.orovecchia.com"
  tag.48875632.key:                   "" => "KubernetesCluster"
  tag.48875632.propagate_at_launch:   "" => "true"
  tag.48875632.value:                 "" => "dev.k8s.orovecchia.com"
  vpc_zone_identifier.#:              "" => "1"
  vpc_zone_identifier.397707395:      "" => "subnet-9f43bec4"
  wait_for_capacity_timeout:          "" => "10m"
aws_security_group_rule.ssh-external-to-master: Creation complete
aws_security_group_rule.all-master-to-node: Creation complete
aws_security_group_rule.all-master-to-master: Creation complete
aws_security_group_rule.ssh-external-to-node: Creation complete
aws_security_group_rule.master-egress: Creation complete
aws_launch_configuration.nodes-dev-k8s-orovecchia-com: Creation complete
aws_autoscaling_group.nodes-dev-k8s-orovecchia-com: Creating...
  arn:                                "" => "<computed>"
  availability_zones.#:               "" => "<computed>"
  default_cooldown:                   "" => "<computed>"
  desired_capacity:                   "" => "<computed>"
  force_delete:                       "" => "false"
  health_check_grace_period:          "" => "300"
  health_check_type:                  "" => "<computed>"
  launch_configuration:               "" => "nodes.dev.k8s.orovecchia.com-20160928200632508897246s2w"
  max_size:                           "" => "2"
  metrics_granularity:                "" => "1Minute"
  min_size:                           "" => "2"
  name:                               "" => "nodes.dev.k8s.orovecchia.com"
  protect_from_scale_in:              "" => "false"
  tag.#:                              "" => "3"
  tag.125196166.key:                  "" => "Name"
  tag.125196166.propagate_at_launch:  "" => "true"
  tag.125196166.value:                "" => "nodes.dev.k8s.orovecchia.com"
  tag.1967977115.key:                 "" => "k8s.io/role/node"
  tag.1967977115.propagate_at_launch: "" => "true"
  tag.1967977115.value:               "" => "1"
  tag.48875632.key:                   "" => "KubernetesCluster"
  tag.48875632.propagate_at_launch:   "" => "true"
  tag.48875632.value:                 "" => "dev.k8s.orovecchia.com"
  vpc_zone_identifier.#:              "" => "1"
  vpc_zone_identifier.397707395:      "" => "subnet-9f43bec4"
  wait_for_capacity_timeout:          "" => "10m"
aws_security_group_rule.all-node-to-master: Still creating... (10s elapsed)
aws_security_group_rule.node-egress: Still creating... (10s elapsed)
aws_security_group_rule.node-egress: Creation complete
aws_security_group_rule.all-node-to-master: Creation complete
aws_autoscaling_group.master-us-east-1a-masters-dev-k8s-orovecchia-com: Still creating... (10s elapsed)
aws_autoscaling_group.nodes-dev-k8s-orovecchia-com: Still creating... (10s elapsed)
aws_autoscaling_group.master-us-east-1a-masters-dev-k8s-orovecchia-com: Still creating... (20s elapsed)
aws_autoscaling_group.nodes-dev-k8s-orovecchia-com: Still creating... (20s elapsed)
aws_autoscaling_group.master-us-east-1a-masters-dev-k8s-orovecchia-com: Still creating... (30s elapsed)
aws_autoscaling_group.nodes-dev-k8s-orovecchia-com: Still creating... (30s elapsed)
aws_autoscaling_group.master-us-east-1a-masters-dev-k8s-orovecchia-com: Still creating... (40s elapsed)
aws_autoscaling_group.nodes-dev-k8s-orovecchia-com: Still creating... (40s elapsed)
aws_autoscaling_group.master-us-east-1a-masters-dev-k8s-orovecchia-com: Still creating... (50s elapsed)
aws_autoscaling_group.master-us-east-1a-masters-dev-k8s-orovecchia-com: Creation complete
aws_autoscaling_group.nodes-dev-k8s-orovecchia-com: Still creating... (50s elapsed)
aws_autoscaling_group.nodes-dev-k8s-orovecchia-com: Still creating... (1m0s elapsed)
aws_autoscaling_group.nodes-dev-k8s-orovecchia-com: Creation complete

Apply complete! Resources: 32 added, 0 changed, 0 destroyed.

The state of your infrastructure has been saved to the path
below. This state is required to modify and destroy your
infrastructure, so keep it safe. To inspect the complete state
use the `terraform show` command.

State path: terraform.tfstate
```

And that is pretty much everything there is to it, I was now able to connect to Kubernetes via kubectl.

``` bash
brew install kubectl
```

``` bash
kubectl cluster-info
```

``` example
Kubernetes master is running at https://api.dev.k8s.orovecchia.com
KubeDNS is running at https://api.dev.k8s.orovecchia.com/api/v1/proxy/namespaces/kube-system/services/kube-dns
```

Now onto creating the application:

Creating our application
------------------------

For our demo application, we are going to use a simple (static) web page. Let's bundle this into a Docker container. First, our site itself:

``` html
 <!DOCTYPE html>
<html>
  <head>
    <meta charset="UTF-8">
    <title>Hello there</title>
  </head>
  <body>
 Automation for the People 
  </body>
</html>
```

Not very sophisticated, but it get's the job done. Let's use golang as our http server (again, this is just for demonstration purposes; If you are really thinking about doing something THAT complicated just to serve a static web page, have a look at [this blog post](http://blog.oro.nu/post/deploying-hugo-with-vagrant-and-saltstack/) instead. Still complex, but far less convoluted.)

```
package main

import (
  "log"
  "net/http"
)

func main() {
  fs := http.FileServer(http.Dir("static"))
  http.Handle("/", fs)
  log.Println("Listening on 8080...")
  http.ListenAndServe(":8080", nil)
}
```

And our build instructions, courtesy of Wercker

```
box: golang
dev:
  steps:
    - setup-go-workspace:
        package-dir: ./

    - internal/watch:
        code: |
          go build -o app ./...
          ./app
        reload: true

build:
  steps:
    - setup-go-workspace:
        package-dir: ./

    - golint

    - script:
        name: go build
        code: |
          CGO_ENABLED=0 go build -a -ldflags '-s' -installsuffix cgo -o app ./...

    - script:
        name: go test
        code: |
          go test ./...

    - script:
        name: copy to output dir
        code: |
          cp -r source/static source/kube.yml app $WERCKER_OUTPUT_DIR
```

``` bash
wercker dev --publish 8080
```

This wercker file + command will automatically reload our local dev environment when we change things, so it will come in quite handy once we start developing new features. I can now access the page running on localhost:8080

``` 
GET http://localhost:8080
```

``` example
HTTP/1.1 200 OK
Content-Type: application/json; charset=utf-8
Date: Tue, 25 Oct 2016 14:13:18 GMT
Expires: Thu, 01 Jan 1970 00:00:00 GMT
Server: Jetty(9.2.11.v20150529)
Set-Cookie: PL=rancher;Path=/
Vary: Accept-Encoding, User-Agent
X-Api-Account-Id: 1a1
X-Api-Client-Ip: 10.0.2.2
X-Api-Schemas: http://localhost:8080/v1/schemas
Content-Length: 333

{"type":"collection","resourceType":"apiVersion","links":{"self":"http://localhost:8080/","latest":"http://localhost:8080/v1"},"createTypes":{},"actions":{},"data":[{"id":"v1","type":"apiVersion","links":{"self":"http://localhost:8080/v1"},"actions":{}}],"sortLinks":{},"pagination":null,"sort":null,"filters":{},"createDefaults":{}}
```

``` example
HTTP/1.1 200 OK
Accept-Ranges: bytes
Content-Length: 155
Content-Type: text/html; charset=utf-8
Last-Modified: Thu, 29 Sep 2016 19:23:33 GMT
Date: Thu, 29 Sep 2016 19:23:40 GMT

<!DOCTYPE html>
<html>
  <head>
    <meta charset="UTF-8">
    <title>Hello there</title>
  </head>
  <body>
 Automation for the People 
  </body>
</html>
```

Also, a `wercker build` will trigger a complete build step, including linting and testing (which we do not have yet).

Now, building locally is nice, however we'd like to create a complete pipeline, so that our CI server can also do the builds. Thankfully, with our `wercker.yml` file we already did that. All that is now needed is to add our repository into [our wercker account](https://app.wercker.com/Haftcreme/simple-nginx-on-docker/runs) and it should automatically trigger after a git push.

Let's have a look via the REST API (the most important part, the `result` that passed)

``` 
GET https://app.wercker.com/api/v3/runs/57ed6b9318c4c70100453a9e
```

``` javascript
{
  "id": "57ed6b9318c4c70100453a9e",
  "url": "https://app.wercker.com/api/v3/runs/57ed6b9318c4c70100453a9e",
  "branch": "master",
  "commitHash": "01c72c62576fc1193753f8080b7acda38796936c",
  "createdAt": "2016-09-29T19:29:23.560Z",
  "envVars": [],
  "finishedAt": "2016-09-29T19:29:39.694Z",
  "message": "wercker file",
  "commits": [
    {
      "by": "Marco Orovecchia",
      "commit": "01c72c62576fc1193753f8080b7acda38796936c",
      "message": "wercker file",
      "_id": "57ed6b9318c4c70100453a9f"
    }
  ],
  "progress": 100,
  "result": "passed",
  "startedAt": "2016-09-29T19:29:25.322Z",
  "status": "finished",
  "user": {
    "meta": {
      "werckerEmployee": false,
      "type": "user",
      "username": "Haftcreme"
    },
    "userId": "56df0dae1618a4fe2c13ed78",
    "avatar": {
      "gravatar": "26b1d4db0a76cdfbc2e95fff776b01fd"
    },
    "name": "Haftcreme",
    "type": "wercker"
  },
  "pipeline": {
    "id": "57ed520918c4c70100451ad8",
    "url": "https://app.wercker.com/api/v3/pipelines/57ed520918c4c70100451ad8",
    "createdAt": "2016-09-29T17:40:25.546Z",
    "name": "build",
    "permissions": "public",
    "pipelineName": "build",
    "setScmProviderStatus": true,
    "type": "git"
  }
}
// GET https://app.wercker.com/api/v3/runs/57ed6b9318c4c70100453a9e
// HTTP/1.1 200 OK
// Content-Type: application/json; charset=utf-8
// Date: Tue, 25 Oct 2016 14:13:19 GMT
// ETag: W/"dd2QmuFCQuPQ1248Bk11Zw=="
// Server: nginx
// Strict-Transport-Security: max-age=10886400; includeSubDomains; preload
// Vary: Accept-Encoding
// X-Content-Type-Options: nosniff
// X-Frame-Options: DENY
// X-Powered-By: Express
// Content-Length: 1001
// Connection: keep-alive
// Request duration: 0.720144s
```

``` javascript
{
  "pipeline": {
    "type": "git",
    "setScmProviderStatus": true,
    "pipelineName": "build",
    "permissions": "public",
    "name": "build",
    "createdAt": "2016-09-29T17:40:25.546Z",
    "url": "https://app.wercker.com/api/v3/pipelines/57ed520918c4c70100451ad8",
    "id": "57ed520918c4c70100451ad8"
  },
  "user": {
    "type": "wercker",
    "name": "Haftcreme",
    "avatar": {
      "gravatar": "26b1d4db0a76cdfbc2e95fff776b01fd"
    },
    "userId": "56df0dae1618a4fe2c13ed78",
    "meta": {
      "username": "Haftcreme",
      "type": "user",
      "werckerEmployee": false
    }
  },
  "status": "finished",
  "startedAt": "2016-09-29T19:29:25.322Z",
  "result": "passed",
  "progress": 100,
  "commits": [
    {
      "_id": "57ed6b9318c4c70100453a9f",
      "message": "wercker file",
      "commit": "01c72c62576fc1193753f8080b7acda38796936c",
      "by": "Marco Orovecchia"
    }
  ],
  "message": "wercker file",
  "finishedAt": "2016-09-29T19:29:39.694Z",
  "envVars": [],
  "createdAt": "2016-09-29T19:29:23.560Z",
  "commitHash": "01c72c62576fc1193753f8080b7acda38796936c",
  "branch": "master",
  "url": "https://app.wercker.com/api/v3/runs/57ed6b9318c4c70100453a9e",
  "id": "57ed6b9318c4c70100453a9e"
}
// GET https://app.wercker.com/api/v3/runs/57ed6b9318c4c70100453a9e
// HTTP/1.1 200 OK
// Content-Type: application/json; charset=utf-8
// Date: Thu, 29 Sep 2016 19:33:10 GMT
// ETag: W/"dd2QmuFCQuPQ1248Bk11Zw=="
// Server: nginx
// Strict-Transport-Security: max-age=10886400; includeSubDomains; preload
// Vary: Accept-Encoding
// Vary: Accept-Encoding
// X-Content-Type-Options: nosniff
// X-Frame-Options: DENY
// X-Powered-By: Express
// Content-Length: 1001
// Connection: keep-alive
// Request duration: 0.716355s
```

Building our deployment pipeline
--------------------------------

Now that we've build our application, we still need a place to store the artifacts. For this, we are going to use the [Docker Registry](https://hub.docker.com/r/oronu/nginx-simple-html/) by Docker. I've added the deploy step to the `wercker.yml` and the two environment variables, `USERNAME` and `PASSWORD` via the Wercker GUI.

```
deploy-dockerhub:
  steps:
    - internal/docker-scratch-push:
        username: $USERNAME
        password: $PASSWORD
        tag: latest, $WERCKER_GIT_COMMIT, $WERCKER_GIT_BRANCH
        cmd: ./app
        ports: 8080
        repository: oronu/nginx-simple-html
        registry: https://registry.hub.docker.com
```

However, at first I was using the `internal/docker-push` step, which resulted in a whopping 256MB container. After reading through [minimal containers](http://devcenter.wercker.com/docs/containers/minimal-containers.html), I changed it to `docker-scratch-push` instead, which resulted in a 1MB image instead. Also, I forgot to actually include the static files at first, which I also remedied afterwards.

Now all that's left is to publish this to our Kubernetes cluster.

Putting everything together
---------------------------

For the last step, we are going to add the deployment to our Kubernetes cluster into the `wercker.yml`. This again needs several environment variables which will be set at the Wercker GUI.

``` 
kube-deploy:
  steps:
    - script:
      name: generate kube file
      code: |
        eval "cat <<EOF
        $(cat "$WERCKER_SOURCE_DIR/kube.yml")
        EOF" > kube-gen.yml
        cat kube-gen.yml
    - kubectl:
      server: $KUBERNETES_MASTER
      username: $KUBERNETES_USERNAME
      password: $KUBERNETES_PASSWORD
      insecure-skip-tls-verify: true
      command: apply -f kube-gen.yml
```

Additionally, I've added the `kube.yml` file which contains [service](http://kubernetes.io/docs/user-guide/services/) and [deployment](http://kubernetes.io/docs/user-guide/deployments/) definitions for Kubernetes.

```
---
kind: Service
apiVersion: v1
metadata:
  name: orohttp-${WERCKER_GIT_BRANCH}
spec:
  ports:
    - port: 80
      targetPort: http-server
      protocol: TCP
  type: LoadBalancer
  selector:
    name: orohttp-${WERCKER_GIT_BRANCH}
    branch: ${WERCKER_GIT_BRANCH}
    commit: ${WERCKER_GIT_COMMIT}
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: orohttp-${WERCKER_GIT_BRANCH}
spec:
  replicas: 2
  template:
    metadata:
      labels:
        name: orohttp-${WERCKER_GIT_BRANCH}
        branch: ${WERCKER_GIT_BRANCH}
        commit: ${WERCKER_GIT_COMMIT}
    spec:
      containers:
      - name: orohttp-${WERCKER_GIT_BRANCH}
        image: oronu/nginx-simple-html:${WERCKER_GIT_COMMIT}
        ports:
        - name: http-server
          containerPort: 8080
          protocol: TCP
```

Now unfortunately Kubernetes [does not](https://github.com/kubernetes/features/issues/35) support parameterization inside its template files yet. This could be remedied by building the template files via following script inside the wercker.yml

``` bash
eval "cat <<EOF
$(cat "$1")
EOF"
```

This definition will result in all commits to all branches being automatically deployed. Different branches however will get different loadbalancers and therefore different DNS addresses.

And just to make sure, let's check the actual deployed application:

``` bash
kubectl get svc -o wide
```

``` example
NAME             CLUSTER-IP      EXTERNAL-IP                                                               PORT(S)   AGE       SELECTOR
kubernetes       100.64.0.1      <none>                                                                    443/TCP   55m       <none>
orohttp-master   100.71.47.208   af689c86086eb11e6a0a50e4d6ac19b8-1846451599.us-east-1.elb.amazonaws.com   80/TCP    8m        branch=master,commit=c9c84f1b9b479d2133541b2f3065af1d86559c94,name=orohttp-master
```

``` 
GET af689c86086eb11e6a0a50e4d6ac19b8-1846451599.us-east-1.elb.amazonaws.com
```

``` example
HTTP/1.1 200 OK
Accept-Ranges: bytes
Content-Length: 155
Content-Type: text/html; charset=utf-8
Last-Modified: Fri, 30 Sep 2016 08:57:28 GMT
Date: Fri, 30 Sep 2016 09:06:22 GMT

<!DOCTYPE html>
<html>
  <head>
    <meta charset="UTF-8">
    <title>Hello there</title>
  </head>
  <body>
 Automation for the People 
  </body>
</html>
```

Testing and health checks
-------------------------

Up until now, we are only hoping that our infrastructure and applications are working. Let's make sure of that. However, instead of focusing on (classic) infrastructure tests, let's first make sure that what actually matters is working: The application itself. For this, we can already test our pipeline. Let's start working on our new feature:

``` bash
git flow feature start init-healthcheck
```

``` example

Summary of actions:
- A new branch 'feature-init-healthcheck' was created, based on 'develop'
- You are now on branch 'feature-init-healthcheck'

Now, start committing on your feature. When done, use:

     git flow feature finish init-healthcheck

```

Now we are changing our application so that it responds to a `/healthz` endpoint: (this is taken with slight adaptations from <https://github.com/kubernetes/kubernetes.github.io/blob/master/docs/user-guide/liveness/image/server.go>)

```
/*
Copyright 2014 The Kubernetes Authors All rights reserved.
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
    http://www.apache.org/licenses/LICENSE-2.0
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

// A simple server that is alive for 10 seconds, then reports unhealthy for
// the rest of its (hopefully) short existence.
package main

import (
  "fmt"
  "log"
  "net/http"
  "time"
)

func main() {
  started := time.Now()
  http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
    http.ServeFile(w, r, "static/index.html")
  })
  http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
    duration := time.Now().Sub(started)
    if duration.Seconds() > 10 {
      w.WriteHeader(500)
      w.Write([]byte(fmt.Sprintf("error: %v", duration.Seconds())))
    } else {
      w.WriteHeader(200)
      w.Write([]byte("ok"))
    }

  })
  log.Println(http.ListenAndServe(":8080", nil))
}
```

This application now serves (as before) our index.html from `/` and additionally exposes a `healthz` endpoint that responds with `200 OK` for 10 seconds and `500 error` after that. Basically, we've introduced a bug in our endpoint which does not even surface to a user. Remember that time when your backend silently swallowed every 100th request? Good times...

Now we also need to consume the `healthz` endpoint, which is done in our deployment spec.

```
---
kind: Service
apiVersion: v1
metadata:
  name: orohttp-${WERCKER_GIT_BRANCH}
spec:
  ports:
    - port: 80
      targetPort: http-server
      protocol: TCP
  type: LoadBalancer
  selector:
    name: orohttp-${WERCKER_GIT_BRANCH}
    branch: ${WERCKER_GIT_BRANCH}
    commit: ${WERCKER_GIT_COMMIT}
---
apiVersion: extensions/v1beta1
kind: Deployment
metadata:
  name: orohttp-${WERCKER_GIT_BRANCH}
spec:
  replicas: 2
  template:
    metadata:
      labels:
        name: orohttp-${WERCKER_GIT_BRANCH}
        branch: ${WERCKER_GIT_BRANCH}
        commit: ${WERCKER_GIT_COMMIT}
    spec:
      containers:
      - name: orohttp-${WERCKER_GIT_BRANCH}
        image: oronu/nginx-simple-html:${WERCKER_GIT_COMMIT}
        ports:
        - name: http-server
          containerPort: 8080
          protocol: TCP
        livenessProbe:
          httpGet:
            path: /healthz
            port: http-server
          initialDelaySeconds: 15
          timeoutSeconds: 1
```

With those changes, we can push our new branch into github and check the (new!) endpoint that Kubernetes created.

``` bash
kubectl get svc -o wide
```

``` example
NAME                               CLUSTER-IP       EXTERNAL-IP                                                               PORT(S)   AGE       SELECTOR
kubernetes                         100.64.0.1       <none>                                                                    443/TCP   2h        <none>
orohttp-feature-init-healthcheck   100.65.243.228   ab4871ba286f611e6a0a50e4d6ac19b8-294871847.us-east-1.elb.amazonaws.com    80/TCP    42s       branch=feature-init-healthcheck,commit=6b223dfc4c846e3cff52025356c2cd70c545cb27,name=orohttp-feature-init-healthcheck
orohttp-master                     100.71.47.208    af689c86086eb11e6a0a50e4d6ac19b8-1846451599.us-east-1.elb.amazonaws.com   80/TCP    1h        branch=master,commit=c9c84f1b9b479d2133541b2f3065af1d86559c94,name=orohttp-master
```

``` 
GET ab4871ba286f611e6a0a50e4d6ac19b8-294871847.us-east-1.elb.amazonaws.com
```

``` example
HTTP/1.1 200 OK
Accept-Ranges: bytes
Content-Length: 155
Content-Type: text/html; charset=utf-8
Last-Modified: Fri, 30 Sep 2016 10:14:18 GMT
Date: Fri, 30 Sep 2016 10:17:43 GMT

<!DOCTYPE html>
<html>
  <head>
    <meta charset="UTF-8">
    <title>Hello there</title>
  </head>
  <body>
 Automation for the People 
  </body>
</html>
```

For a user everything looks fine, however when we check the actual pod definitions we can see that they die after a short time

``` bash
kubectl get pods
```

``` example
NAME                                                READY     STATUS             RESTARTS   AGE
orohttp-feature-init-healthcheck-1833998652-5k6vo   0/1       CrashLoopBackOff   5          3m
orohttp-feature-init-healthcheck-1833998652-n0ggi   0/1       CrashLoopBackOff   5          3m
orohttp-master-3020287202-dhii1                     1/1       Running            0          1h
orohttp-master-3020287202-icqgp                     1/1       Running            0          1h
```

Let's fix that:

```

/*
Copyright 2014 The Kubernetes Authors All rights reserved.
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at
    http://www.apache.org/licenses/LICENSE-2.0
Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

// A simple server that is alive for 10 seconds, then reports unhealthy for
// the rest of its (hopefully) short existence.
package main

import (
  "log"
  "net/http"
)

func main() {
  http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
    http.ServeFile(w, r, "static/index.html")
  })
  http.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
    w.WriteHeader(200)
    w.Write([]byte("ok"))
  })
  log.Println(http.ListenAndServe(":8080", nil))
}
```

``` example
The Deployment "orohttp-feature-init-healthcheck" is invalid.
spec.template.metadata.labels: Invalid value: {"branch":"feature-init-healthcheck","commit":"latest","name":"orohttp-feature-init-healthcheck"}: `selector` does not match template `labels`
```

Uh-oh, this is not related to our build file but to our infrastructure. This seems to be caused by <https://github.com/kubernetes/kubernetes/issues/26202> and seems to suggest that changing selectors (what we are using for the load balancer to know which containers to switch in) is not a good idea but instead creating new load balancers. For our use case, let's simply remove the commit label since it is not needed anyways (the commit is already referenced as the image itself)

After that is fixed, let's recheck our deployment

``` bash
kubectl get pods
```

``` example
NAME                                               READY     STATUS    RESTARTS   AGE
orohttp-feature-init-healthcheck-568167226-mm7uf   1/1       Running   0          1m
orohttp-feature-init-healthcheck-568167226-xvokv   1/1       Running   0          1m
orohttp-master-3020287202-dhii1                    1/1       Running   0          1h
orohttp-master-3020287202-icqgp                    1/1       Running   0          1h
```

Much better. Let's finish our work with a merge to master and recheck our deployment one last time.

``` bash
git flow feature finish init-healthcheck
git push
```

``` example
Merge made by the 'recursive' strategy.
 app.go   | 31 +++++++++++++++++++++++++------
 kube.yml |  8 ++++++--
 2 files changed, 31 insertions(+), 8 deletions(-)
Deleted branch feature-init-healthcheck (was 1e24202).

Summary of actions:
- The feature branch 'feature-init-healthcheck' was merged into 'develop'
- Feature branch 'feature-init-healthcheck' has been removed
- You are now on branch 'develop'
```

``` bash
kubectl get deployments,pods
```

``` example
NAME                                               DESIRED   CURRENT   UP-TO-DATE   AVAILABLE   AGE
orohttp-develop                                    2         2         2            2           47s
orohttp-feature-init-healthcheck                   2         2         2            2           7m
NAME                                               READY     STATUS    RESTARTS     AGE
orohttp-develop-3627383002-joyey                   1/1       Running   0            47s
orohttp-develop-3627383002-nk3me                   1/1       Running   0            47s
orohttp-feature-init-healthcheck-568167226-mm7uf   1/1       Running   0            7m
orohttp-feature-init-healthcheck-568167226-xvokv   1/1       Running   0            7m
```

Cleanup
-------

``` bash
terraform plan -destroy 
```

``` example
Refreshing Terraform state in-memory prior to plan...
The refreshed state will be used to calculate this plan, but
will not be persisted to local or remote state storage.

aws_iam_role.nodes-dev-k8s-orovecchia-com: Refreshing state... (ID: nodes.dev.k8s.orovecchia.com)
aws_iam_role.masters-dev-k8s-orovecchia-com: Refreshing state... (ID: masters.dev.k8s.orovecchia.com)
aws_key_pair.kubernetes-dev-k8s-orovecchia-com-952344bf29bc219a86d3bc12f1767073: Refreshing state... (ID: kubernetes.dev.k8s.orovecchia.com-95:23:44:bf:29:bc:21:9a:86:d3:bc:12:f1:76:70:73)
aws_vpc.dev-k8s-orovecchia-com: Refreshing state... (ID: vpc-7821081f)
aws_ebs_volume.us-east-1a-etcd-main-dev-k8s-orovecchia-com: Refreshing state... (ID: vol-192822be)
aws_ebs_volume.us-east-1a-etcd-events-dev-k8s-orovecchia-com: Refreshing state... (ID: vol-3d28229a)
aws_vpc_dhcp_options.dev-k8s-orovecchia-com: Refreshing state... (ID: dopt-023f6d66)
aws_iam_role_policy.masters-dev-k8s-orovecchia-com: Refreshing state... (ID: masters.dev.k8s.orovecchia.com:masters.dev.k8s.orovecchia.com)
aws_iam_instance_profile.masters-dev-k8s-orovecchia-com: Refreshing state... (ID: masters.dev.k8s.orovecchia.com)
aws_iam_instance_profile.nodes-dev-k8s-orovecchia-com: Refreshing state... (ID: nodes.dev.k8s.orovecchia.com)
aws_iam_role_policy.nodes-dev-k8s-orovecchia-com: Refreshing state... (ID: nodes.dev.k8s.orovecchia.com:nodes.dev.k8s.orovecchia.com)
aws_internet_gateway.dev-k8s-orovecchia-com: Refreshing state... (ID: igw-dbf906bc)
aws_vpc_dhcp_options_association.dev-k8s-orovecchia-com: Refreshing state... (ID: dopt-023f6d66-vpc-7821081f)
aws_security_group.nodes-dev-k8s-orovecchia-com: Refreshing state... (ID: sg-e67d289c)
aws_subnet.us-east-1a-dev-k8s-orovecchia-com: Refreshing state... (ID: subnet-9f43bec4)
aws_route_table.dev-k8s-orovecchia-com: Refreshing state... (ID: rtb-6cd35a0a)
aws_security_group.masters-dev-k8s-orovecchia-com: Refreshing state... (ID: sg-e17d289b)
aws_security_group_rule.node-egress: Refreshing state... (ID: sgrule-2872475010)
aws_security_group_rule.ssh-external-to-node: Refreshing state... (ID: sgrule-71065845)
aws_security_group_rule.all-node-to-node: Refreshing state... (ID: sgrule-30692617)
aws_launch_configuration.nodes-dev-k8s-orovecchia-com: Refreshing state... (ID: nodes.dev.k8s.orovecchia.com-20160928200632508897246s2w)
aws_route.0-0-0-0--0: Refreshing state... (ID: r-rtb-6cd35a0a1080289494)
aws_route_table_association.us-east-1a-dev-k8s-orovecchia-com: Refreshing state... (ID: rtbassoc-9441fbed)
aws_security_group_rule.master-egress: Refreshing state... (ID: sgrule-3088574993)
aws_security_group_rule.all-master-to-node: Refreshing state... (ID: sgrule-1685541623)
aws_security_group_rule.https-external-to-master: Refreshing state... (ID: sgrule-3920636886)
aws_security_group_rule.ssh-external-to-master: Refreshing state... (ID: sgrule-1693229204)
aws_security_group_rule.all-master-to-master: Refreshing state... (ID: sgrule-1006626549)
aws_security_group_rule.all-node-to-master: Refreshing state... (ID: sgrule-1583145227)
aws_launch_configuration.master-us-east-1a-masters-dev-k8s-orovecchia-com: Refreshing state... (ID: master-us-east-1a.masters.dev.k8s.orovecchia.com-201609282006304731484157ff)
aws_autoscaling_group.nodes-dev-k8s-orovecchia-com: Refreshing state... (ID: nodes.dev.k8s.orovecchia.com)
aws_autoscaling_group.master-us-east-1a-masters-dev-k8s-orovecchia-com: Refreshing state... (ID: master-us-east-1a.masters.dev.k8s.orovecchia.com)

The Terraform execution plan has been generated and is shown below.
Resources are shown in alphabetical order for quick scanning. Green resources
will be created (or destroyed and then created if an existing resource
exists), yellow resources are being changed in-place, and red resources
will be destroyed. Cyan entries are data sources to be read.

Note: You didn't specify an "-out" parameter to save this plan, so when
"apply" is called, Terraform can't guarantee this is what will execute.

- aws_autoscaling_group.master-us-east-1a-masters-dev-k8s-orovecchia-com

- aws_autoscaling_group.nodes-dev-k8s-orovecchia-com

- aws_ebs_volume.us-east-1a-etcd-events-dev-k8s-orovecchia-com

- aws_ebs_volume.us-east-1a-etcd-main-dev-k8s-orovecchia-com

- aws_iam_instance_profile.masters-dev-k8s-orovecchia-com

- aws_iam_instance_profile.nodes-dev-k8s-orovecchia-com

- aws_iam_role.masters-dev-k8s-orovecchia-com

- aws_iam_role.nodes-dev-k8s-orovecchia-com

- aws_iam_role_policy.masters-dev-k8s-orovecchia-com

- aws_iam_role_policy.nodes-dev-k8s-orovecchia-com

- aws_internet_gateway.dev-k8s-orovecchia-com

- aws_key_pair.kubernetes-dev-k8s-orovecchia-com-952344bf29bc219a86d3bc12f1767073

- aws_launch_configuration.master-us-east-1a-masters-dev-k8s-orovecchia-com

- aws_launch_configuration.nodes-dev-k8s-orovecchia-com

- aws_route.0-0-0-0--0

- aws_route_table.dev-k8s-orovecchia-com

- aws_route_table_association.us-east-1a-dev-k8s-orovecchia-com

- aws_security_group.masters-dev-k8s-orovecchia-com

- aws_security_group.nodes-dev-k8s-orovecchia-com

- aws_security_group_rule.all-master-to-master

- aws_security_group_rule.all-master-to-node

- aws_security_group_rule.all-node-to-master

- aws_security_group_rule.all-node-to-node

- aws_security_group_rule.https-external-to-master

- aws_security_group_rule.master-egress

- aws_security_group_rule.node-egress

- aws_security_group_rule.ssh-external-to-master

- aws_security_group_rule.ssh-external-to-node

- aws_subnet.us-east-1a-dev-k8s-orovecchia-com

- aws_vpc.dev-k8s-orovecchia-com

- aws_vpc_dhcp_options.dev-k8s-orovecchia-com

- aws_vpc_dhcp_options_association.dev-k8s-orovecchia-com


Plan: 0 to add, 0 to change, 32 to destroy.
```

``` bash
terraform destroy -force
```

``` example
Error applying plan:

2 error(s) occurred:

 aws_ebs_volume.us-east-1a-etcd-events-dev-k8s-orovecchia-com: Error deleting EC2 volume vol-3d28229a: VolumeInUse: Volume vol-3d28229a is currently attached to i-1a27720c
    status code: 400, request id: a1df6173-5f72-4c43-90d4-8a723f32dcd4
 aws_ebs_volume.us-east-1a-etcd-main-dev-k8s-orovecchia-com: Error deleting EC2 volume vol-192822be: VolumeInUse: Volume vol-192822be is currently attached to i-1a27720c
    status code: 400, request id: 1ce03a4f-1b81-4868-9586-57047ffb1afa

Terraform does not automatically rollback in the face of errors.
Instead, your Terraform state file has been partially updated with
any resources that successfully completed. Please address the error
above and apply again to incrementally change your infrastructure.
```

Oh well, looks like Terraform (or rather, AWS) did not update its state soon enough. No issue though, you can simply rerun the command.

``` bash
terraform destroy -force
```

Voila. However, Kubernetes [reccomends](https://github.com/kubernetes/kops/blob/master/docs/terraform.md) to also use Kops to delete the cluster to make sure that any potential ELBs or volumes resulted during the usage of Kubernetes are cleaned up as well.

``` bash
~/golang/bin/kops delete cluster --yes dev.k8s.orovecchia.com --state=s3://oro-kops-state 
```

Links
-----

-   [Dockerhub container image](https://hub.docker.com/r/oronu/nginx-simple-html/tags/)
-   [Wercker pipeline](https://app.wercker.com/Haftcreme/simple-nginx-on-docker/runs)
-   [Demo application + infrastructure files](https://github.com/Oro/simple-nginx-on-docker)

ToDos
-----

Now granted this is not a comprehensive guide.

-   It is still missing any sort of notification in case something goes wrong
-   There is no automatic cleanup of deployments
-   There is no automatic rollback in case of errors
-   And, above all: This is **extremely** complicated just to host a simple web page. Again, for only static files, you are much better of using something like [GitHub pages](https://pages.github.com/) or even [S3](http://docs.aws.amazon.com/AmazonS3/latest/dev/WebsiteHosting.html).

Closing remarks
---------------

Would I reccomend using Kubernetes? ABSOLUTELY.

Not only is Kubernetes extremely sophisticated, it is also advancing at an incredible speed. For reference, I've tried it out around a year ago with V0.18, and it did not yet have Deployments, Pets, Batch Jobs or ConfigMaps, all of which are incredibly helpful.

Having said that, I am not sure if I'd necessarily reccomend Wercker. Granted, it works nicely - when it works. I've ran into several panics when trying to run the wercker cli locally, NO output whatsoever on the web GUI if the working directory does not exist, and the documentation is severely outdated. It is still in beta, yes, however if this is an indication of things to come that I am not sure if I would like to bet on it for something as critical as a CI server.

TL;DR
-----

To bootstrap a kubernetes cluster:

``` bash
kops create cluster --zones=us-east-1a dev.k8s.orovecchia.com --state=s3://oro-kops-state --yes
```

To push a new version of our code or infrastructure:

``` bash
wercker deploy --pipeline kube-deploy
```
