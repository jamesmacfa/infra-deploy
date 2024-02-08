# Phrase interview task

This repo contains the IaC I used to deploy the supplied python application. Before reading further, there are two caveats. I time-boxed this exercise and did not have time left for two elements: 

1. HTTPS
2. The second Postgres read-only user

While implementation of the latter is fairly straightforward, I'd like to address how I'd handle the former given more time. The spec mentions self-signed or lets encrypt, but realistically I'd purchase a domain through Route 53 or similar, use ACM, and add the certificate to the load balancer/listener. In an ideal world, I'd have all of this deployed in k8s, and so certificates would be handled with cert-manager.

This repo contains two primary components: 

## Terraform

The Terraform included defines 

1. A load balancer, with rules to forward to an EC2 target group on port 5000, as well as to exclude both of the deployment rules
2. A VPC, subnets, and security group rules.
3. Two EC2 instances, with some user data configuration for public keys and user adds.
4. A managed redis instance - this is, in my view, more robust than running a redis cluster manually. However, if this was running in k8s, I may end up doing that. 
5. A managed Postgres instance. Regardless of Kubernetes or directly managed EC2s, I'd still use this setup.
6. An image repository/registry. This setup builds the docker image locally and then runs it, all on the EC2s. In a real world scenario, I'd build on a runner, push to a registry, and pull that image. The inclusion of this component is indicative, and is not used here. 

## Ansible 

The ansible included does the following: 

1. Installs Docker
2. Checks whether the application is currently running.
3. If it is running, it hits the deployment endpoints and only proceeds if deploy is Ready/200 response. 
4. Stops the old container. 
5. Builds and runs the new container. 

The endpoints for redis, postgres, and the IP addresses of the EC2 machines are provided as outputs in the Terraform code. These need to be manually added to the playbook and inventory files, respectively.

## How do I run it?

Terraform and Ansible should be installed locally. Template values for public keys in the Terraform should be populated (as part of a CI/CD pipeline these would be pulled in from repo secrets). The AWS CLI should be installed and properly authenticated. IAM permissions would be pretty broad for this setup, and so I won't try to list them here. Once this has been done, the Terraform can be run from the terraform directory: 

```
terraform init

terraform plan

terraform apply
```

As mentioned, the outputs from this, should the run be successful, should be used for the relevant playbook.yml and inventory fields. 

NOTE: I had to manually create the palindrom database via psql in the managed instance, before running the supplied create_db.py. 

From the top level of this repo, ansible can be run via: 

```
ansible-playbook -i inventory playbook.yaml -u <your_ssh_username_here>
```

To avoid downtime, the ansible playbook updates the nodes sequentially (although the load balancer health checks may make this redundant, as it won't route to an unhealthy instance). 

Once ansible has run, the load balancer endpoint can be used to verify functionality. 

## What would I change? 

I'd run this as part of a CI/CD pipeline given more time. Ideally Github actions/Gitlab CI. At various points here things are hard coded for expediency - I'd pull this data out and template more.

I'd also definitely deploy this to a Kubernetes cluster, and have NGINX/the ingress controller handle the path blocking/basic auth at that level. ConfigMaps/secrets for environment config, a service attached to an ingress to route between pods, and some horizontal auto-scaling for the pods. I considered going with this approach here, but thought it would be overkill for a small web app.
