# Kubernetes Guide (Docker Only): Run Salary Management Locally and on AWS

This guide needs **only Docker Desktop**. You do not install minikube, kind, Helm,
the AWS CLI, eksctl, or anything else on your Mac.

- **Local:** we use the Kubernetes that is already inside Docker Desktop.
- **AWS:** we run the AWS tools *inside Docker containers* through two tiny wrapper scripts.

The app has two parts:

| Part | What it is | Port |
|---|---|---|
| `api/` | Rails API with a SQLite database file | 3000 |
| `web/` | React app (built once, then served by Rails from `api/public`) | 5173 in dev |

> SQLite is a **file**, not a database server. So you can run only **one copy
> (1 replica)** of the API. Two copies would write to two different files.

---

## Part 0. Basic words (read once)

| Word | Simple meaning |
|---|---|
| **Image** | A packed box with your app and everything it needs. |
| **Container** | A running copy of an image. |
| **Kubernetes (K8s)** | A manager that starts, restarts, and connects containers. |
| **Cluster** | The machines Kubernetes controls. |
| **Pod** | The smallest unit. It wraps one container. |
| **Deployment** | A rule: "keep N pods of this app running". |
| **Service** | A fixed address that finds your pods. |
| **Namespace** | A folder inside the cluster. |
| **Secret** | A place for private settings. |
| **PVC** | A request for disk space that survives restarts. |
| **kubectl** | The command line tool to talk to Kubernetes. Docker Desktop includes it. |

---

## Part 1. What you need

| Need | For | Notes |
|---|---|---|
| **Docker Desktop** | Local and AWS | You already have it. Use a recent version. |
| **kubectl** | Local and AWS | Comes **inside** Docker Desktop. Nothing to install. |
| **AWS account** | AWS only | **Costs money.** See the warning in Section 2. |
| **AWS login on your Mac** (a `~/.aws` folder from SSO or keys) | AWS only | Used by the wrapper scripts in Section 2. |

Check that Docker is ready:

```bash
docker --version          # prints the Docker version
kubectl version --client  # prints the kubectl version (comes with Docker Desktop)
```

If `kubectl` is not found, open Docker Desktop once and make sure it is running.

Docker Desktop settings tip: if your Mac gets slow, go to Settings > Resources and
lower CPU and memory (about 4 CPU and 6 to 8 GB is enough).

---

## Section 1. LOCAL: Run the app on Kubernetes with Docker Desktop

### Step 1. Turn on Kubernetes in Docker Desktop

1. Open Docker Desktop.
2. Go to **Settings > Kubernetes**.
3. Switch on **Enable Kubernetes**. If it asks for a type, choose **Kubeadm** (one node).
4. Click **Apply & restart**. Wait for the Kubernetes light at the bottom to turn green.
   The first time can take a few minutes.

Check that it works. These commands ask the local cluster to show itself:

```bash
kubectl config use-context docker-desktop    # point kubectl at the Docker Desktop cluster
kubectl get nodes                            # should show 1 node, Ready
```

### Step 2. Make a production Dockerfile

The project has only `api/Dockerfile.dev` (for development). For Kubernetes you want
an image that **contains the code**. Create `api/Dockerfile`:

```dockerfile
# ---- Stage 1: build the React app ----
FROM node:22-slim AS web
WORKDIR /web
COPY web/package*.json ./
RUN npm ci
COPY web/ ./
# vite builds into ../api/public, so make that folder exist
RUN mkdir -p /api/public && npm run build

# ---- Stage 2: the Rails app ----
FROM ruby:3.4-slim
RUN apt-get update -qq && apt-get install --no-install-recommends -y \
      build-essential libsqlite3-dev libyaml-dev pkg-config git curl tzdata \
    && rm -rf /var/lib/apt/lists/*

ENV RAILS_ENV=production \
    BUNDLE_DEPLOYMENT=1 \
    BUNDLE_WITHOUT="development:test" \
    RAILS_SERVE_STATIC_FILES=true

WORKDIR /app
COPY api/Gemfile api/Gemfile.lock ./
RUN bundle install
COPY api/ ./
# bring in the built React files
COPY --from=web /api/public ./public

EXPOSE 3000
CMD ["bin/rails", "server", "-b", "0.0.0.0", "-p", "3000"]
```

Also create a `.dockerignore` in the project root so secrets and heavy folders stay
out of the image:

```
**/node_modules
**/.git
api/log
api/tmp
api/storage
api/coverage
api/config/master.key
**/.env*
```

> If the build fails, open `web/vite.config.ts` and check that the build output goes
> to `../api/public`. The paths must match.

### Step 3. Build the image

Run this **from the project root**. It reads the Dockerfile and makes an image named
`salary-api:local`. The last `.` means "use the project root".

```bash
docker build -f api/Dockerfile -t salary-api:local .
```

With Docker Desktop Kubernetes (Kubeadm), the cluster uses the **same image store as
Docker**. So the image is already visible to Kubernetes. There is no "load image" step.

Optional quick test without Kubernetes (open http://localhost:3000, stop with Ctrl+C):

```bash
docker run --rm -p 3000:3000 -e SECRET_KEY_BASE=$(openssl rand -hex 64) salary-api:local
```

### Step 4. Fix and apply the namespace

Your [00-name-space.yaml](00-name-space.yaml) has a small mistake: the line
`app.kubernetes.io/part-of` is directly under `metadata`, but it is a **label**, so it
must be inside `labels:`. Kubernetes will reject the file as written. Use this:

```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: salary-management
  labels:
    app.kubernetes.io/part-of: salary-management
```

Apply it (this creates the "folder" for your app):

```bash
kubectl apply -f k8s/00-name-space.yaml
```

### Step 5. Write the app files

Create these files in `k8s/`.

**`k8s/01-secret.yaml`**: private settings. Do **not** commit real values.
A fake value is fine for local testing.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: salary-api-secret
  namespace: salary-management
type: Opaque
stringData:
  SECRET_KEY_BASE: "replace-me-with-a-long-random-string"
```

Or skip the file and create the secret from the command line:

```bash
kubectl -n salary-management create secret generic salary-api-secret \
  --from-literal=SECRET_KEY_BASE="$(openssl rand -hex 64)"
```

> Rails production may also want `RAILS_MASTER_KEY` (from `api/config/master.key`).
> That file is private. Add it to the Secret yourself if the app needs it, and never
> commit it.

**`k8s/02-storage.yaml`**: disk for the SQLite file, so data survives restarts.

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: salary-sqlite
  namespace: salary-management
spec:
  accessModes: ["ReadWriteOnce"]
  resources:
    requests:
      storage: 1Gi
```

**`k8s/03-deployment.yaml`**: runs the API pod.

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: salary-api
  namespace: salary-management
  labels:
    app.kubernetes.io/part-of: salary-management
spec:
  replicas: 1                  # must stay 1 because SQLite is a single file
  strategy:
    type: Recreate             # stop the old pod before starting the new one
  selector:
    matchLabels:
      app: salary-api
  template:
    metadata:
      labels:
        app: salary-api
    spec:
      containers:
        - name: api
          image: salary-api:local
          imagePullPolicy: IfNotPresent   # use the image we built on this machine
          ports:
            - containerPort: 3000
          env:
            - name: RAILS_ENV
              value: production
            - name: RAILS_LOG_TO_STDOUT
              value: "1"
            - name: SECRET_KEY_BASE
              valueFrom:
                secretKeyRef:
                  name: salary-api-secret
                  key: SECRET_KEY_BASE
          volumeMounts:
            - name: sqlite
              mountPath: /app/storage
          readinessProbe:               # "is the app ready for traffic?"
            httpGet:
              path: /up                 # Rails 8 default health check
              port: 3000
            initialDelaySeconds: 10
            periodSeconds: 10
          resources:
            requests: { cpu: "100m", memory: "256Mi" }
            limits:   { cpu: "500m", memory: "512Mi" }
      volumes:
        - name: sqlite
          persistentVolumeClaim:
            claimName: salary-sqlite
```

> If your API has no `/up` route, change the path to one that returns 200.

**`k8s/04-service.yaml`**: a stable address for the pod. On Docker Desktop, a
`NodePort` is reachable on `localhost`.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: salary-api
  namespace: salary-management
spec:
  type: NodePort
  selector:
    app: salary-api
  ports:
    - port: 3000
      targetPort: 3000
      nodePort: 30080
```

### Step 6. Deploy

```bash
kubectl apply -f k8s/            # applies every yaml file in the folder
kubectl -n salary-management get pods -w
```

Wait until the pod shows `1/1 Running`, then press Ctrl+C.

> `kubectl apply -f k8s/` reads only `.yaml`, `.yml` and `.json` files, so this guide
> and the wrapper scripts are ignored.

### Step 7. Prepare the database and open the app

`exec` runs a command inside the running pod:

```bash
kubectl -n salary-management exec deploy/salary-api -- bin/rails db:prepare
kubectl -n salary-management exec deploy/salary-api -- bin/rails db:seed   # the 10k-row seed
```

Open the app: **http://localhost:30080**

If that address does not open, use port-forward (keeps running; stop with Ctrl+C), then
open http://localhost:3000:

```bash
kubectl -n salary-management port-forward svc/salary-api 3000:3000
```

### Step 8. Useful everyday commands

```bash
kubectl -n salary-management get all                    # list everything
kubectl -n salary-management logs deploy/salary-api -f  # follow the logs
kubectl -n salary-management describe pod <pod-name>    # why is a pod unhappy?
kubectl -n salary-management rollout restart deploy/salary-api
```

After you change code, rebuild and restart:

```bash
docker build -f api/Dockerfile -t salary-api:local .
kubectl -n salary-management rollout restart deploy/salary-api
```

### Step 9. Clean up

```bash
kubectl delete -f k8s/                  # remove the app
```

To free more memory, turn Kubernetes off in Docker Desktop (Settings > Kubernetes).

### Local problems and fixes

| Problem | Likely cause and fix |
|---|---|
| `kubectl get nodes` cannot connect | Kubernetes is not on or not ready. Check Step 1 and the green light. |
| Wrong cluster | Run `kubectl config use-context docker-desktop`. |
| `ImagePullBackOff` or `ErrImageNeverPull` | The image is not visible to the cluster. Use the **Kubeadm** type in Step 1 and keep `imagePullPolicy: IfNotPresent`. |
| `CrashLoopBackOff` | Read `kubectl logs`. Often a missing `SECRET_KEY_BASE`. |
| Pod `Pending` | PVC not bound or low RAM. Run `kubectl describe pod`. |
| `database is locked` | More than 1 replica. Keep `replicas: 1`. |

---

## Section 2. AWS: Run the same app on Amazon EKS (Docker only)

> **WARNING: THIS COSTS MONEY.** An EKS cluster costs about **$0.10 per hour** for the
> control plane, **plus** servers (nodes), disk, and load balancer. Usually a few
> dollars per day. **Delete everything when you finish** (Step 11). Set a budget alert
> first: AWS Console > Billing > Budgets. Check current prices before you start.

### How "Docker only" works here

AWS has its own tools (`aws` and `eksctl`). Instead of installing them, we run each
one inside a Docker container. A tiny script named `aws` and a tiny script named
`eksctl` hide the long `docker run` command. `kubectl` also needs an `aws` program on
your PATH to get a login token for EKS, so these scripts must be on your PATH.

> The scripts mount your `~/.aws` folder **read-only** so the container can use your
> AWS login. That folder holds your AWS credentials. Only continue if you are happy
> with that. Never copy or share that folder.

### Step 1. Log in to AWS (do this in a way that gives you `~/.aws`)

You need an existing AWS login on your Mac (SSO or access keys already in `~/.aws`).
If you have none, create an IAM user or SSO profile in the AWS Console with rights for
EKS, EC2, ECR, IAM, and CloudFormation, then follow the steps AWS shows for it.

You will check it in Step 3.

### Step 2. Make the two wrapper scripts

Create the folder and files:

```bash
mkdir -p k8s/bin
```

**`k8s/bin/aws`**

```bash
#!/bin/sh
# Runs the AWS CLI inside Docker. No install needed.
exec docker run --rm -i \
  -v "$HOME/.aws:/root/.aws:ro" \
  -e AWS_PROFILE -e AWS_REGION -e AWS_DEFAULT_REGION \
  amazon/aws-cli "$@"
```

**`k8s/bin/eksctl`**

```bash
#!/bin/sh
# Runs eksctl inside Docker. No install needed.
# The cluster login file is kept in k8s/.kube-aws, NOT in your normal ~/.kube/config,
# so your local Docker Desktop setup is not touched.
mkdir -p "$PWD/k8s/.kube-aws"
exec docker run --rm -i \
  -v "$HOME/.aws:/root/.aws:ro" \
  -v "$PWD/k8s/.kube-aws:/kube" \
  -e AWS_PROFILE -e AWS_REGION -e AWS_DEFAULT_REGION \
  -e KUBECONFIG=/kube/config \
  weaveworks/eksctl "$@"
```

Make them runnable, and tell your **current terminal only** to use them. (This does not
change your shell config files. It lasts until you close the terminal.)

```bash
chmod +x k8s/bin/aws k8s/bin/eksctl
export PATH="$PWD/k8s/bin:$PATH"
export KUBECONFIG="$PWD/k8s/.kube-aws/config"     # kubectl now talks to AWS in this terminal
```

Add these two lines to `.gitignore` so login files never get committed:

```
k8s/.kube-aws/
```

> Important: run all AWS steps in the **same terminal**, from the project root. In a
> new terminal, repeat the two `export` lines. To go back to local Kubernetes, close
> the terminal, or run `unset KUBECONFIG`.

### Step 3. Check the AWS login and set values

```bash
aws --version                  # runs inside Docker; first time it downloads the image
aws sts get-caller-identity    # shows who you are; proves you are logged in
```

If you use SSO and it says the token expired, run `aws sso login` and follow the link.
(The container cannot open your browser, so copy the link it prints.)

Set handy values (change the region if you like):

```bash
export AWS_REGION=ap-south-1
export CLUSTER=salary-eks
export ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export ECR_URI=$ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/salary-api
```

### Step 4. Make image storage (ECR) and push the image

```bash
# 1. Create the repository
aws ecr create-repository --repository-name salary-api

# 2. Log Docker in to ECR
aws ecr get-login-password | \
  docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# 3. Build for the cluster's CPU type and push
#    (Apple Silicon Macs are arm64. The nodes below are amd64, so we force amd64.)
docker buildx build --platform linux/amd64 -f api/Dockerfile -t $ECR_URI:v1 --push .
```

> If you see "exec format error" later, the image CPU type does not match the nodes.
> Keep `--platform linux/amd64` with `t3` nodes.

### Step 5. Create the cluster

Takes about 15 to 20 minutes. It makes the network, the cluster, and 1 small node,
and it saves the login file into `k8s/.kube-aws/config`.

```bash
eksctl create cluster \
  --name $CLUSTER \
  --region $AWS_REGION \
  --nodegroup-name workers \
  --node-type t3.medium \
  --nodes 1 \
  --managed
```

Check that `kubectl` now points to AWS:

```bash
kubectl config current-context
kubectl get nodes          # 1 node, Ready
```

### Step 6. Turn on disk support (EBS driver)

The PVC needs a driver that creates real AWS disks.

```bash
eksctl utils associate-iam-oidc-provider --cluster $CLUSTER --region $AWS_REGION --approve

eksctl create iamserviceaccount \
  --name ebs-csi-controller-sa --namespace kube-system \
  --cluster $CLUSTER --region $AWS_REGION \
  --role-name AmazonEKS_EBS_CSI_DriverRole \
  --role-only --approve \
  --attach-policy-arn arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy

eksctl create addon --name aws-ebs-csi-driver --cluster $CLUSTER --region $AWS_REGION \
  --service-account-role-arn arn:aws:iam::$ACCOUNT_ID:role/AmazonEKS_EBS_CSI_DriverRole --force
```

An EBS disk lives in **one zone**. With `replicas: 1` and one node this is fine.

### Step 7. Change the files for AWS

Do **not** edit your local files. Copy them so local still works:

```bash
cp -r k8s k8s-aws
rm -rf k8s-aws/bin k8s-aws/.kube-aws k8s-aws/Kubernetes-Guide.md k8s-aws/Architecture.md
```

In `k8s-aws/03-deployment.yaml`, change the image and pull policy.
(Run `echo $ECR_URI:v1` to see the exact text to paste.)

```yaml
          image: <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/salary-api:v1
          imagePullPolicy: Always
```

In `k8s-aws/04-service.yaml`, use a **LoadBalancer**. AWS then makes a public address:

```yaml
spec:
  type: LoadBalancer
  selector:
    app: salary-api
  ports:
    - port: 80
      targetPort: 3000
```

(Remove the `nodePort` line.)

### Step 8. Create the secret and deploy

```bash
kubectl apply -f k8s-aws/00-name-space.yaml

# Create the secret from the command line (not stored in any file)
kubectl -n salary-management create secret generic salary-api-secret \
  --from-literal=SECRET_KEY_BASE="$(openssl rand -hex 64)"

# Apply the rest (skip 01-secret.yaml, we made the secret above)
kubectl apply -f k8s-aws/02-storage.yaml -f k8s-aws/03-deployment.yaml -f k8s-aws/04-service.yaml

kubectl -n salary-management get pods -w
```

Wait for `1/1 Running`.

### Step 9. Prepare the database

```bash
kubectl -n salary-management exec deploy/salary-api -- bin/rails db:prepare
kubectl -n salary-management exec deploy/salary-api -- bin/rails db:seed
```

### Step 10. Find the public address and test

```bash
kubectl -n salary-management get svc salary-api
```

Look at the `EXTERNAL-IP` column. It is a long name like
`abc123.ap-south-1.elb.amazonaws.com`. It can take 2 to 5 minutes to appear.
Open `http://<that-name>` in your browser, or test it:

```bash
curl -i http://<that-name>/up
```

To update the app later:

```bash
docker buildx build --platform linux/amd64 -f api/Dockerfile -t $ECR_URI:v2 --push .
kubectl -n salary-management set image deploy/salary-api api=$ECR_URI:v2
kubectl -n salary-management rollout status deploy/salary-api
```

### Step 11. DELETE everything (do not skip this)

Delete the Service first so AWS removes the load balancer, then the cluster, then ECR.

```bash
kubectl delete -f k8s-aws/04-service.yaml
kubectl delete -f k8s-aws/03-deployment.yaml -f k8s-aws/02-storage.yaml   # frees the EBS disk
eksctl delete cluster --name $CLUSTER --region $AWS_REGION
aws ecr delete-repository --repository-name salary-api --force
```

Then open the AWS Console and check **EC2 > Load Balancers**, **EC2 > Volumes**, and
**CloudFormation** to be sure nothing is left. Leftover items keep charging you.

### AWS problems and fixes

| Problem | Likely cause and fix |
|---|---|
| `aws: command not found` or `eksctl: command not found` | You are in a new terminal. Run the two `export` lines from Step 2 again. |
| `kubectl` still shows the local cluster | `KUBECONFIG` is not set in this terminal. Run the `export KUBECONFIG=...` line. |
| `kubectl` says it cannot get a token | The `aws` wrapper is not on PATH, or your login expired. Run `aws sts get-caller-identity`. |
| `ImagePullBackOff` | Wrong image name, or the repo is in another region. Check the image text and region. |
| `exec format error` | CPU type mismatch. Rebuild with `--platform linux/amd64`. |
| PVC stays `Pending` | EBS driver missing (Step 6). |
| `EXTERNAL-IP` stays `<pending>` | Wait a few minutes, then `kubectl describe svc salary-api`. |
| `AccessDenied` or `UnauthorizedOperation` | Your AWS user lacks rights. Ask for EKS, EC2, and IAM permissions. |

---

## Section 3. Summary: Local vs AWS

| | Local (Docker Desktop) | AWS (EKS) |
|---|---|---|
| Cluster | Built into Docker Desktop (toggle in Settings) | `eksctl` running in Docker |
| Image location | Your local Docker (no load step) | Pushed to ECR |
| Service type | `NodePort`, open `localhost:30080` | `LoadBalancer`, public AWS address |
| Disk | Docker Desktop's local disk | EBS volume |
| Extra installs | None | None (wrapper scripts only) |
| Cost | Free | Paid, delete when done |
| Time to start | A few minutes | About 20 minutes |

## Section 4. Safe habits

- Never commit `config/master.key`, `.env` files, real Secret values, or `k8s/.kube-aws/`.
- Keep `replicas: 1` while the app uses SQLite. To scale out later, move to a real
  database such as Postgres (RDS on AWS).
- Always run the clean-up steps when you finish.
- This guide is for learning and testing. For real production you would add HTTPS,
  database backups, and monitoring.
