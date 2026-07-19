# SWE 645 — Assignment 2: Containerization, EKS Deployment, and Jenkins CI/CD

**Author:** Lizon Raj
**Course:** SWE 645 — Software Systems Design and Implementation
**Institution:** George Mason University
**Submission type:** Individual

---

## Overview

This project takes the static HTML site from Assignment 1 (Part 2), containerizes it with Docker, deploys it to an Amazon EKS Kubernetes cluster with 3 self-healing replicas behind an AWS Load Balancer, and wires a Jenkins CI/CD pipeline that automatically redeploys the site on every push to `main`.

**End-to-end flow:**

```
Developer  --git push-->  GitHub  --webhook-->  Jenkins (on EC2)
                                                   |
                                                   +-- docker build + push --> Docker Hub
                                                   |
                                                   +-- kubectl set image ---> EKS cluster
                                                                                 |
                                                                                 +-- Pod 1
                                                                                 +-- Pod 2 --> AWS Load Balancer --> Users
                                                                                 +-- Pod 3
```

---

## Repository layout

```
lizon-swe645-hw2/
├── site/                      # Static HTML from Assignment 1 Part 2
│   ├── index.html             #   Landing page
│   ├── survey.html            #   Campus visit survey form
│   └── images/                #   Referenced images
├── k8s/                       # Kubernetes manifests
│   ├── deployment.yaml        #   Deployment: 3 replicas, probes, resource limits
│   └── service.yaml           #   Service: LoadBalancer, port 80
├── Dockerfile                 # nginx:1.27-alpine base + COPY site/
├── .dockerignore              # Excludes .DS_Store, .git, README from image
├── .gitignore                 # Excludes local build artifacts
├── Jenkinsfile                # Declarative CI/CD pipeline (5 stages)
├── docs/
│   └── SWE645-HW2-Documentation.pdf   # Detailed writeup + screenshots
└── README.md                  # This file
```

---

## Tools and versions

| Component | Version / Choice | Why |
|---|---|---|
| Base image | `nginx:1.27-alpine` | Small (~23 MB), production-grade static server |
| Kubernetes | EKS 1.30 | Managed control plane, no self-hosting overhead |
| Worker nodes | 2 × `t3.medium` in `us-east-1` | Enough for 3 pods + kube-system with headroom |
| CI/CD | Jenkins 2.568 on EC2 (`t3.small`, Amazon Linux 2023) | Assignment-specified |
| Container registry | Docker Hub (`lizonraj/lizon-swe645-hw2`, public, multi-arch amd64+arm64) | Free, EKS pulls without auth |
| Provisioning tools | `eksctl`, `awscli` v2, `kubectl` v1.30, `buildx` | Standard EKS + Docker tooling |

---

## Docker Hub image

Public, multi-architecture:

```
docker pull lizonraj/lizon-swe645-hw2:latest
docker pull lizonraj/lizon-swe645-hw2:v0.1.1
```

Tag format:
- `latest` — latest successful build
- `vX.Y.Z` — manual semantic release tags
- `<git-short-sha>` — per-commit immutable tag pushed by Jenkins (e.g., `4309ba4`)

---

## Live deployment

The application is deployed on Kubernetes at the LoadBalancer URL provisioned by the running EKS cluster:

```
http://<elb-hostname>.us-east-1.elb.amazonaws.com/            # index.html
http://<elb-hostname>.us-east-1.elb.amazonaws.com/survey.html # survey form
```

The exact ELB URL rotates each time the cluster is recreated. During the demo period the current URL is captured in `docs/SWE645-HW2-Documentation.pdf` and the accompanying video. **Per the assignment, the application does not need to be live for grading** — reproduction steps below re-create the deployment from scratch.

---

## Reproduce the deployment

### Prerequisites (on your local machine)

- Docker Desktop (for building the image)
- `awscli` v2 configured with credentials for an account that can create EKS + EC2 + IAM resources
- `eksctl` (>= 0.180)
- `kubectl` (any 1.28+ client)
- A Docker Hub account (or edit `IMAGE` in `Jenkinsfile` and manifests to point elsewhere)

### 1. Build and push the image locally

```bash
docker buildx create --name multiarch --use
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t lizonraj/lizon-swe645-hw2:latest \
  -t lizonraj/lizon-swe645-hw2:v0.1.1 \
  --push .
```

### 2. Create the EKS cluster (~15 min)

```bash
eksctl create cluster \
  --name lizon-swe645 \
  --region us-east-1 \
  --node-type t3.medium \
  --nodes 2 \
  --managed \
  --version 1.30
```

`eksctl` writes the kubeconfig automatically.

### 3. Deploy the app

```bash
kubectl apply -f k8s/
kubectl get pods -l app=lizon-site -w   # wait for 3/3 Running
kubectl get svc lizon-site-svc -w       # wait for EXTERNAL-IP to appear (3-5 min)
```

Once the LoadBalancer URL appears, the site is live at `http://<url>/`.

### 4. Provision Jenkins EC2 with IAM instance profile

Full commands are documented in `docs/SWE645-HW2-Documentation.pdf`. In summary:

- Create an IAM role (`JenkinsEC2Role`) with `eks:DescribeCluster` permission and an EC2 trust policy.
- Attach as an instance profile (`JenkinsEC2Profile`).
- Grant the role EKS cluster-admin via an **access entry**:
  ```bash
  aws eks create-access-entry \
    --cluster-name lizon-swe645 --region us-east-1 \
    --principal-arn arn:aws:iam::<ACCOUNT_ID>:role/JenkinsEC2Role \
    --type STANDARD
  aws eks associate-access-policy \
    --cluster-name lizon-swe645 --region us-east-1 \
    --principal-arn arn:aws:iam::<ACCOUNT_ID>:role/JenkinsEC2Role \
    --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSAdminPolicy \
    --access-scope type=cluster
  ```
- Launch a `t3.small` EC2 with a security group opening SSH from your IP and TCP 8080 from anywhere. Attach the instance profile.
- User-data script installs Java 21, Docker, `kubectl`, Jenkins; adds the `jenkins` user to the `docker` group.

### 5. Configure Jenkins

- Unlock with `/var/lib/jenkins/secrets/initialAdminPassword`.
- Install suggested plugins + **Docker Pipeline**, **Kubernetes CLI**, **GitHub**.
- Add Docker Hub credentials as **Username with password** with ID `dockerhub-creds`. **Use a Docker Hub Personal Access Token as the password** — Hub rejects account passwords for CLI auth when 2FA is enabled.
- Create a **Pipeline** job pointing to this GitHub repo with "Pipeline script from SCM" and script path `Jenkinsfile`. Enable **GitHub hook trigger for GITScm polling**.

### 6. Wire the GitHub webhook

- GitHub repo → Settings → Webhooks → Add webhook.
- Payload URL: `http://<jenkins-ec2-public-ip>:8080/github-webhook/` (**trailing slash required**).
- Content type: `application/json`. Events: **Just the push event**.

### 7. End-to-end test

Make any visible change to `site/index.html`, then:

```bash
git add . && git commit -m "test" && git push origin main
```

Jenkins fires within ~10 seconds, builds a new image tagged with the commit SHA, pushes it to Docker Hub, updates the EKS Deployment via `kubectl set image`, and waits for the rollout to complete. Refresh the ELB URL — the new content appears within ~2 minutes.

---

## CI/CD pipeline stages (Jenkinsfile)

| Stage | What it does |
|---|---|
| **Checkout** | Pulls the repo at the pushed commit. |
| **Compute tag** | Captures the 7-char short SHA of `HEAD` — the immutable image tag for this build. |
| **Docker build** | Builds one image, tags it `:$SHA` and `:latest`. |
| **Docker push** | Logs into Docker Hub using `dockerhub-creds` (password piped via stdin so it never appears in logs). Pushes both tags. |
| **Deploy to EKS** | `kubectl set image` changes the Deployment spec — Kubernetes rolls out new pods. `kubectl rollout status` blocks until pods are Ready or the pipeline times out. |
| **Post cleanup** | `docker logout` and `docker image prune` regardless of build outcome. |

The pipeline enforces a per-stage 15-minute timeout and keeps only the last 10 build histories to save disk on the `t3.small` Jenkins host.

---

## Kubernetes design notes

**Deployment (`k8s/deployment.yaml`):**
- 3 replicas — meets the assignment's high-availability requirement.
- Image pinned to `:v0.1.1` initially; Jenkins overrides via `kubectl set image` per build. `imagePullPolicy: IfNotPresent` is safe because SHA-tagged images are immutable.
- **Readiness probe** on `/` port 80 (delay 3s, period 5s) — keeps a pod out of the Service until nginx is serving.
- **Liveness probe** on `/` port 80 (delay 10s, period 15s) — restarts a pod if nginx wedges. This is the self-healing mechanism the assignment requires.
- Modest resource requests/limits (50m→200m CPU, 64Mi→128Mi memory) — nginx serving static files needs almost nothing.

**Service (`k8s/service.yaml`):**
- Type `LoadBalancer` — AWS provisions a Classic ELB with a public hostname, forwards port 80 to the pods.
- Selector `app: lizon-site` matches Deployment pod labels.

---

## Cost hygiene

Running the full stack (EKS + NAT gateway + ELB + Jenkins EC2) costs approximately:
- **~$0.30/hour** while active
- **~$120–150/month** if left on continuously

**Always tear down between sessions:**

```bash
eksctl delete cluster --name lizon-swe645 --region us-east-1 --wait
aws ec2 terminate-instances --instance-ids <jenkins-ec2-id> --region us-east-1
```

An AWS Budget alert at $10/month is armed on the deployment account to catch accidental long-running resources.

---

## Documentation and video

- **Detailed writeup:** `docs/SWE645-HW2-Documentation.pdf`
- **Narrated demo video:** included in submission package (or linked from documentation PDF)
- **Grading URL:** the current live ELB URL is documented in the PDF and shown in the video; per the assignment, the application does not need to be live for grading.

---

## Repository

- **GitHub:** https://github.com/Lizonraj/lizon-swe645-hw2
- **Docker Hub:** https://hub.docker.com/r/lizonraj/lizon-swe645-hw2

---

*Submitted for SWE 645, George Mason University.*
