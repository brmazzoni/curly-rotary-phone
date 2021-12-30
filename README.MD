Curly Rotary Phone - A ML System Experiment for the DigitalOcean Kubernetes Challenge 2021

Abstract: TODO

Objectives: the goal of this experiment is to learn how Kubernetes, and DigitalOcean managed Kubernetes could (or could not) be used to support a scalable machine learning and data management system.

Use case: the applied use case is a world-wide B2B organization scope meaning that:
- It is assumed that the traffic will not be extensive: 
    - A few hundreads to thousands of user
    - Up to 1 or 2 hundreads simultaneous connections
- It is assumed that the ML tasks will be demanding in terms of CPU and GPU.
- It is required to have good bandwidth performance in order to access the assets in a fluid way from different world-wide locations

Questions:
- Is it possible to easily "scale geographically" using DigitalOcean managed Kubernetes (meaning serve assets from a cluster node situaded in different geographic locations depending on where the user is localized to maximize performance)?
- Is it possible to easily scale the computing infrastructure depding on computing performance needs for ML tasks?
    - CPU resources?
    - GPU/TPU resources?
    - What is the impact to cost?
- Is it possible to easily interface on-prem storage solution for archival of data?
- Are Load Balancer Services a good solution for this use case? if not, what are the alternatives?
- 


Steps and Achievements:

1. spin up a Kubernetes Cluster on DigitalOcean and deploy a first application
Note: this was done by following the "Getting Started with Digital Ocean Kubernetes". Summary of the steps:
- Set up a basic Flask app that will print the hostname of the host machine:
    - with main.py and requirements.txt (available in "starter" folder):
        - tested locally the app:
            python3 venv venv
            source venv/bin/activate
            pip install Flask
            python main.py

        - access http://localhost:8080 and check it displays the hostname

- Built docker image using VSCode Docker Extension and a DockerFile (available in "starter" folder)
    - for some reason, I could not access the app when running it through Docker Desktop, but decided to move forward
- install doctl (on macos):
    brew install doctl
- Created a DigitalOcean image registry.
- Pushed the image to the registry
- used doctl to spin up a kubernetes cluster:
    doctl kubernetes cluster create curlyrotarycluster
- check the nodes are running:
    kubectl get nodes
- Give access to the repository from the cluster (in repository settings on digitalocean.com)
- Using the deployment file (available in "starter" folder), deploy the pods on the cluster:
    kubectl create -f deployment.yaml
- check the pods are running:
    kubectl get pods

- Using the service file (available in "starter" folder), kick off a load balancer service to expose the app to the Internet:
    kubectl create -f service.yaml
- After a few minutes, access the service information including an external IP:
    kubectl get services
- Access the app, refresh and check that it is printing the hostname of different replicas (name of the containers)
- Cleanup:
    kubectl delete service py-service
    kubectl delete deploy python-deployment

Achievements: App was correctly running with 3 replicas. Load Balancer service granted access to the 3 different replicas. After the test was done, the 2 above commands allowed shuting down the app and Load Balancer

2. Deploy Kubeflow on the cluster
- clone kubeflow's manifests repo:
    git clone https://github.com/kubeflow/manifests.git
- install kustomize (on macos):
    brew install kustomize
- run the install command for kubeflow example (will install all available functions, will take a while):
    while ! kustomize build example | kubectl apply -f -; do echo "Retrying to apply resources"; sleep 10; done
- OR alternatively follow the readme in kubeflow manifests repository to install a custom list of the needed microservices
- Setup port forwarding to access the app (assuming istio service was installed in the case of a custom installation):
    kubectl port-forward svc/istio-ingressgateway -n istio-system 8080:80
- Access the portal at http://localhost:8080, with default credentials provided in the kubeflow manifests repo's readme.





Findings:
- DigitalOcean creates a Kubernetes cluster in a given region. All nodes in the cluster will be located in the same computing infrastructure. By default, this does not easily allow to "scale geographically"
- It is possible to use a port forwarding service to access the application without serving it over http.
- Kubeflow does not have a "DigitalOcean distribution" yet. A manifests repository is available and allows "1 command line" full installation, but documentation is not that clear and it can be challenging to reach operational status.
- Terraform will not allow spinning up a kubernetes cluster pool on the most basic droplets
- Jupyterhub notebooks request 1G of memory by default, so unless you selected a large RAM pool size, you need to specify lower memory requests and limits in the config.yaml for jupyterhub.



Open issues:
- Is port forwarding an acceptable option to access the tools in production for the use case?
- Problems with mounting volumes on stop and restart of a jupyterhub server




---------

## REBOOT - Automating GitOps and Continuous Delivery with DOKS based implementation

### Prerequisites:
- Create github repo
- create clusters/dev folder
- commit and push the readme
- generate a token in github with repo access (Account settings > developer > token)
- set up doctl with a digital ocean token (already done in starter)
- Create a digital ocean Space
- Generate a space access key from the API menu in digital ocean
- Export the key and secret as environmental variables
- install required tools (git, doctl, kubectl, flux, terraform, kubeseal)... all brew install(able)
    - install flux: brew install fluxcd/tap/flux

### Init Terraform Backend
- create config/terraform/backend.tf (copy the template in DOKS starter kit 15>assets>terraform)
- change the region in the digital ocean url; name; to reflect the one where the space was created
- no need to change the "region" parameter
- key: terraform.tfstate
- Then get the main.tf file and populate it with your github, do parameters and cluster name and config (see slugs.do-api.dev)
- in terraform directory, run terraform init  --backend-config="access_key=$DO_SPACES_ACCESS_KEY" --backend-config="secret_key=$DO_SPACES_SECRET_KEY"

### bootstraping DOKS and flux cd
- terraform plan -out starter_kit_flux_cluster.out
- terraform apply "starter_kit_flux_cluster.out"
- after the cluster is created, check the space contains the tfstate file
- check access to cluster by running: doctl k8s clsuter list
- savec kubecongig: doctl k8s cluster kubeconfig save curly-rotary-cluster
- kubectl config get-contexts
- kubectl get nodes
- kubectl get pods -A
- kubectl get ns
- kubectl get all -n flux-system

### Flux CD
- flux check
- flux get all
- kubectl get gitrepositories.source.toolkit.fluxcd.io -n flux-system

- pull the changes from terraform to your repo: git pull origin
- create clusters/dev/helm/repositories, clusters/dev/helm/secrets and clusters/dev/flux-system/helm/releases
- export FLUXCD_HELM_MANIFESTS_PATH="[...]/curly-rotary-phone/clusters/dev/helm"
- run:

flux create source helm sealed-secrets \
  --url="https://bitnami-labs.github.io/sealed-secrets" \
  --interval="10m" \
  --export > "${FLUXCD_HELM_MANIFESTS_PATH}/repositories/sealed-secrets.yaml"

- run:

SEALED_SECRETS_CHART_VERSION="1.16.1"

curl "https://raw.githubusercontent.com/digitalocean/Kubernetes-Starter-Kit-Developers/main/08-kubernetes-sealed-secrets/assets/manifests/sealed-secrets-values-v${SEALED_SECRETS_CHART_VERSION}.yaml" > "sealed-secrets-values-v${SEALED_SECRETS_CHART_VERSION}.yaml"

- run:

SEALED_SECRETS_CHART_VERSION="1.16.1"

flux create helmrelease "sealed-secrets-controller" \
  --release-name="sealed-secrets-controller" \
  --source="HelmRepository/sealed-secrets" \
  --chart="sealed-secrets" \
  --chart-version "$SEALED_SECRETS_CHART_VERSION" \
  --values="sealed-secrets-values-v${SEALED_SECRETS_CHART_VERSION}.yaml" \
  --target-namespace="flux-system" \
  --crds=CreateReplace \
  --export > "${FLUXCD_HELM_MANIFESTS_PATH}/releases/sealed-secrets-v${SEALED_SECRETS_CHART_VERSION}.yaml"


- commit the manifests
- flux reconcile source git flux-system
- flux get helmrelease sealed-secrets-controller



----

Utilities

- kubctl deploy -f utils.yaml
- kubectl exec utilities-..... -it -- /bin/sh