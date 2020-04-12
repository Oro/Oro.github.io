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

and applied it

``` bash
terraform apply 1-initial
```


That looks promising, and with a quick glance at the AWS console I could confirm that Terraform had indeed boostrapped a t2.micro instance in the us-east-1. I destroyed it quickly afterwards to incur little to no costs via

``` bash
terraform destroy -force 1-initial
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

This will create the terraform files in `out/terraform`, setup the Kubernetes config in `~/.kube/config` and store the [state](https://github.com/kubernetes/kops/blob/master/docs/state.md) of Kops inside an S3 bucket. This has the benefit that a) other team members (potentially) can modify the cluster and b) the infrastructure itself can be safely stored within a repository

Let's spawn the cluster

``` bash
terraform plan
```

``` bash
terraform apply
```

And that is pretty much everything there is to it, I was now able to connect to Kubernetes via kubectl.

``` bash
brew install kubectl
```

``` bash
kubectl cluster-info
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

Not very sophisticated, but it gets the job done. Let's use golang as our http server (again, this is just for demonstration purposes; If you are really thinking about doing something THAT complicated just to serve a static web page, have a look at [this blog post](http://blog.oro.nu/post/deploying-hugo-with-vagrant-and-saltstack/) instead. Still complex, but far less convoluted.)

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

Now we are changing our application so that it responds to a `/healthz` endpoint: (this is taken with slight adaptations from [here](https://github.com/kubernetes/kubernetes.github.io/blob/master/docs/user-guide/liveness/image/server.go))

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
