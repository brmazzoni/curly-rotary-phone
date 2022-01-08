# Benchmarking Deep Neural Network with Jupyterlab on Kubernetes - A ML System Experiment for the DigitalOcean Kubernetes Challenge 2021

## Abstract

Jupyter notebook are a core component of many ML system. I used jupyterlab project that has a one liner installation process as well as extensive documentation for kubernetes deployment. 
I ran a small number of benchmarks on a few of the basic droplet sizes available in order to get an idea of the gain of performance when manually scaling up the nodes. 
I finally experienced with the pool size configurations and the helm config file for jupyterlab to better exploit the autoscaling feature. 
I obtained best results using 2GB memory nodes size and configure the user memory limits to 1.4G.
Regarding CPU, AMD premium CPUs perform noticeably better than Intel ones for my ML application and dual CPU provides a considerable gain over single CPU.


## Step-by-step description of the final setup:

/!\ WARNING: this walkthrough does not describe how to secure the application. Without protecting it using a VPC/VPN or a stronger auth scheme, it is only a matter of days before someone will maliciously exploit the resources in your cluster.

### Prerequisites

For this setup we use the following tools:
- doctl
- kubectl
- terraform
- helm

all of which can be installed with "brew install *package*" if you are running macos and installed homebrew.

### Use terraform to create a DOKS cluster

- Create a DO_TOKEN for terraform from Digital Ocean's account API menu
- (for macos) Add ```export DO_TOKEN="<copy your token here>"``` to the .zprofile (or other prefered method to create environmental variable), and restart the terminal
- cd in the "terraform" folder of the project
- edit the cluster.tf file in the project, change cluster name, region as per your preferences
- edit node pool size depending on needs of the project (I recommend a minimum of 1 to allow economic downscale when the ML system is not being used, and a maximum corresponding to your expected maximum number of simltaneous users + 1 + margin)
- run the following commands:
```
terraform init
```
```
terraform plan -var do_token=$DO_TOKEN
```
![terraform_plan](https://user-images.githubusercontent.com/92771598/148630518-03144103-6e6c-4ab0-802c-67e41b635058.png)
```
terraform apply -var do_token=$DO_TOKEN
```
- type yes to confirm, you will see some messages indicating the cluster is creating:
![terraform_apply](https://user-images.githubusercontent.com/92771598/148630578-eb02f4d4-1411-4551-8af2-68b0f291f38f.png)


- when the cluster is up, type the following command to enable kubectl:
```
doctl kubernetes cluster kubeconfig save <your_cluster_id>
```
![kubectl_config](https://user-images.githubusercontent.com/92771598/148630588-09ce46dc-3bce-426c-8469-64fcd1dee701.png)

Check the installation:
```
kubectl get nodes
```
- you should see 1 pod running (or the minimum number you specified)
![Screenshot 2022-01-08 at 11 45 27](https://user-images.githubusercontent.com/92771598/148630608-ea1b8a8c-a863-4a34-b78e-bda17ec2147e.png)

```
kubectl get pods -A
```
- You should see all the pods running on your cluster.

### Use helm to install JupyterLab

**Resources**:

https://zero-to-jupyterhub.readthedocs.io/en/latest/index.html

https://jupyter-docker-stacks.readthedocs.io/en/latest/using/selecting.html

https://jupyter-docker-stacks.readthedocs.io/en/latest/_images/inherit.svg

- type the following commands:

```
helm repo add jupyterhub https://jupyterhub.github.io/helm-chart/
```

```
helm repo update
```

cd in the jupyterhub folder of the repository and edit the config.yaml file, customize it for:
- image (I use one with tensorflow to run the ML experiment, but other images are available, see links above)
- resources (I recommend limiting the memory to your node memory size minus 600M to 1G to leave some space for other services sharing the node)

The config file is quite minimalistic:
```
singleuser:
  image:
    # You should replace the image and the "latest" tag with a fixed version from:
    # https://hub.docker.com/r/jupyter/
    name: jupyter/tensorflow-notebook
    tag: latest
  memory:
    limit: 1.4G
    guarantee: 1G
```

Enter the follwing command in your terminal (you can copy/paste):
```
helm upgrade --cleanup-on-fail \
  --install jupyterhub jupyterhub/jupyterhub \
  --namespace jhub \
  --create-namespace \
  --version=1.2.0 \
  --values config.yaml
```

**Note**: replace the chart version with the appropriate one from https://jupyterhub.github.io/helm-chart/ (currently latest is 1.2.0)


The Jupyterhub releases gives you out of the box the following feature:
- A linked Digital Ocean Load balancer to expose the app to the internet
- Automatic horizontal pod scaling
- User registration and authentication
- Linked Digital Ocean Volumes to store user's data (a volume is created each time a user is created)
- creates a namespace for the app (make sure to use ```-n jhub``` in your kubectl commands)

In order to connect to the app, let's inspect the cluster services to figure out the public ip:
```
kubectl get svc -n jhub
```
- you should see a LoadBalancer service named "proxy-public", and a  EXTERNAL-IP listed. Copy the IP.
- if the EXTERNAL-IP is <pending>, just wait a couple of minutes and try again... the service takes a little while to come up.
![public_ip](https://user-images.githubusercontent.com/92771598/148630904-0c375876-0b29-4672-a4cf-713154222bc4.png)

From a browser, access the IP and you should land on a connection page. 
- At the moment, no user is created, but you just have to type a user name and a password to have one created. Jupyterhub will then "Spawn a server" (i.e. create a pod in the DOKS cluster from the image you selected in the jupyterhub release). This step may take up to 10 minutes, and may trigger autoscale (creation of a new node). 
- The server spawning may fail, just click the jupyterhub logo to try again (and this time it should not fail anymore becasue the new node is ready)

If the autoscale is triggered, you should see something like this in your browser:
![server_creation_triggered_autoscale](https://user-images.githubusercontent.com/92771598/148630935-30d652bb-2825-4a46-9558-1fa1738eedab.png)


In the meantime, you could monitor your new pod coming up:
```
kubectl get po -n jhub
```

You should see something like this:
![spawn_pod](https://user-images.githubusercontent.com/92771598/148631006-78ce92ae-9737-4f02-ab89-b44bfa53f254.png)

At any given moment, you can check if more nodes are created with:
```
kubectl get nodes
```

And you can check which pods are running (which users are connected with a running server):
```
kubectl get pods -n jhub
```

After users log out, their server will automatically shut down (after a timeout), and eventually, the unused nodes will be automatically terminated (auto-downscale).
The user data is kept in an automatically created DigitalOcean Volume. In order to view the existing volumes linked to the cluster you can use the following command:
```
kubectl get sc -n jhub
```
![volumes](https://user-images.githubusercontent.com/92771598/148631234-f2cf6b40-b4c0-4fbd-b216-fd93b28b07e3.png)


### Deploy the ML experiment

This project provides 2 notebooks with a basic ML experiment in the "notebooks" folder. To deploy it to your server, you could either:
- drag and drop the notebooks files (.ipynb) to the notebook server's file browser (on the left of the user interface)
- or open a terminal in the notebook, and use git to clone the repository inside the notebook.

Then:
- double click on the first notebook (0_prepare.ipynb). 
- Wait a few second to give time to the kernel to start (you will see a grey dot on the tab when the kernel is running)
- Then click on the Run dropdown menu and select "Run all cells"

This notebook will just download a dataset from the NASA website and perform a few data preparation steps.

- double click on the second notebook (1_ML.ipynb) and give it some time for the kernel to start
- Select Run > Run All Cells, or run the cells one by one (you could use Shift+Enter) to inspect the ouput of the ML workflow

This second notebook will configure and train a Deep Neural Network and run train it to guess remaining useful life of some turbofan engines based on a series of sensor measurements (spoiler: as configured now, it doesn't work very well).
![tensorflow_training](https://user-images.githubusercontent.com/92771598/148631167-8bca77cf-b4fd-40ac-adc2-5a91805fa94c.png)

![training_metrics](https://user-images.githubusercontent.com/92771598/148631174-e44bf3a4-eec0-4e43-a946-458164491ff3.png)

### Mini-Benchmark

The ML model training runs with the following performance on different droplet setups:
- s-1vcpu-2gb-amd -> 83 seconds
- s-2vcpu-2gb-intel -> 83 seconds...
- s-2vcpu-2gb-amd -> 60 seconds!
- c-2 -> 57 seconds
- s-4vcpu-8gb-amd -> 53 seconds

Cost (monthly, 0 user - 10 users):
- 1 CPU 2GB AMD: 52$ -> 120$
- 2 CPU 2GB AMD/Intel: 58$ -> 238$
- 4 CPU 4GB AMD: 88$ -> 568$

**Note**: the Load Balancer and the Volumes are billed separately.

Using AMD premium dual CPUs with 2GB RAM droplets for my cluster seems to be a sweet spot in terms of performance/cost ratio.

**Note**: when updating the node sizes, it will be necessary to destroy the old cluster and create a new one, so the jupyterlab release installation will be lost. I recommend to use the Digital Ocean GUI to destroy existing cluster because it will provide the option to destroy all linked resources (Loar balancer, and volumes). ```terraform destroy``` will leave the Load Balancer and Volumes hanging because at the moment it does not know about the jupyterhub installation.

### Adjust the perf specs

The "Scaling a school" tech talk on Digital Ocean Youtube channel describes a similar tech stack. One recommendation from the speaker is to use small nodes that handle 1 user only so the cluster can scale down when the user is offline, so I configured the memory limits for 1 user to 1.4G (600M are used by other services running on each pods).

To reconfigure the performance specs for each user, open the config.yaml in jupyterlab folder, and change the limit and guarantee value with the desired one, then just rerun the helm installation command to apply it.

To have a global view of the performance, inspect the nodes running in your cluster using the following command:
```
kubectl describe pod <pod-name>
```

You will be able to consult a list of resources requests and limit and easily notice if the resources are overcommitted.


## More about the kubernetes experience

Below is a description of other attempts and findings in the Kubernetes Challenge.

**Objectives**: the goal of this experiment is to learn how Kubernetes, and DigitalOcean managed Kubernetes could (or could not) be used to support a scalable machine learning and data management system.

**Use case**: the applied use case is a world-wide B2B organization scope or academic lab, so:
- It is assumed that the traffic will not be extensive: 
    - A few hundreads to thousands of user maximum
    - Up to 1 or 2 hundreads simultaneous connections
- It is assumed that the ML tasks will be demanding in terms of CPU and GPU.
- It is required to have good bandwidth performance in order to access the assets in a fluid way from different world-wide locations

**Questions**:
- Is it possible to easily "scale geographically" using DigitalOcean managed Kubernetes (meaning serve assets from a cluster node situaded in different geographic locations depending on where the user is localized to maximize performance)?
- Is it possible to easily scale the computing infrastructure depding on computing performance needs for ML tasks?
    - CPU resources?
    - GPU/TPU resources?
    - What is the impact to cost?
- Are Load Balancer Services a good solution for this use case? if not, what are the alternatives?

### Summary of the other experiments:

My initial idea was to setup a few micro-services hosted on DOKS to support a ML application. I first experimented with a Kubeflow deployment, but it is highly customizable using the manifests provided by the kubeflow project, it did not work out of the box for me and I had a hard time to find a simple wayforward. 
Jupyter notebook are a core component of many ML system. I then used jupyterlab that has a one liner installation process as well as extensive documentation for kubernetes deployment. 
I later found out that this stack was already the subject of a Digital Ocean talk ("Scaling a school"), exposing interesting findings for a very similar use case as mine.

### Steps and Achievements

- Spin up a Kubernetes Cluster on DigitalOcean and deploy a first application. I tried different methods: 
    - doctl vs terraform to kick the cluster off
    - deploy an application from Digital Ocean container registry

- Deploy Kubeflow on the cluster
    - clone kubeflow's manifests repo:
    ```
    git clone https://github.com/kubeflow/manifests.git
    ```
- install kustomize (on macos):
    ```
    brew install kustomize
    ```
- run the install command for kubeflow example (will install all available functions, will take a while):
    ```
    while ! kustomize build example | kubectl apply -f -; do echo "Retrying to apply resources"; sleep 10; done
    ```
- OR alternatively follow the readme in kubeflow manifests repository to install a custom list of the needed microservices
- Setup port forwarding to access the app (assuming istio service was installed in the case of a custom installation):
```
kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80
```
- Access the portal at http://localhost:8080, with default credentials provided in the kubeflow manifests repo's readme.

At this point I could not find an easy way to spin up jupyterlab servers, had some problems with the secure cookies policy, so I changed my approach.



## Findings
- DigitalOcean creates a Kubernetes cluster in a given region. All nodes in the cluster will be located in the same computing infrastructure. By default, this does not easily allow to "scale geographically".
- Horizontal pod autoscaling was most easy to set up with this tech stack thanks to the integration in Jupyterlab. However Vertical scaling needs to destroy and recreate a new cluster.
- It is possible to use a port forwarding service to access the application without serving it over http, however, I could not assess performances of this solution.
- Kubeflow does not have a "DigitalOcean distribution" yet. A manifests repository is available and allows "1 command line" full installation, but documentation is not that clear and it can be challenging to reach operational status.
- DOKS will not allow spinning up a kubernetes cluster pool on the most basic droplets, at least a configuraiton with 2GB ram is needed, some of the bigger droplet size also are not available (c2-2vcpu-4gb)
- Jupyterhub notebooks request 1G of memory by default, so unless you selected a large RAM pool size, you need to specify lower memory requests and limits in the config.yaml for jupyterhub. By default, with 2GB ram nodes, if autoscale is not enabled, no server will spawn due to insufficuent memory.



## Open issues

- Is port forwarding an acceptable option to access the tools in production for the use case?
- When spawning a jupyterlab server, the corresponding pod is sometimes too long to come up, so the connection times out (but the server can quickly spawn shortly after, when the pod is still available)
- After a cluster is destroyed, is it possible to reuse user authentication and persistent data with a new instance of the cluster? Would allow easier vertical scaling.

## Next steps

- setup https
- customize the jupyterlab image to make it smaller (starts up faster)
- change the timeout value for the server spawning (could I set it in the helm chart?)
- interface other microservices (data pipeline, serve the trained models, user apps...)
- Put terraform backend on a Digital Ocean Space
- Deploy a CI system that works with Jupyter Notebooks

## Acknowledgements

Thanks for Digital Ocean team for organizing the Kubernetes Challenge and offering trial credit allowing us to tinker with DOKS.
Thanks to Jupyterhub project. Jupyter notebooks are a wonderfull tool, but would be nothing without a great platform and community such as jupyterhub supporting it. I particulaly enjoyed how jupyterhub keeps it simple to deploy yet easy to customize.
Thanks to the Prognostics CoE at NASA Ames for providing the turboprop engine degradation dataset used for this ML experiment.
