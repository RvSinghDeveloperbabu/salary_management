# How the cluster looks after `kubectl apply -f k8s/`

Open this file in VS Code. Use a monospace view (the normal editor, or the Markdown preview).
Tip: the diagrams are text, so they look right in any editor.

---

## 1. Words you must know (very short)

| Word | Simple meaning | Docker idea you know |
|---|---|---|
| **Cluster** | The whole Kubernetes system. It is a group of computers working as one. | Your whole Docker setup |
| **Node** | One computer (real or virtual) in the cluster. | The machine running Docker |
| **Control plane node** | The "boss" computer. It decides what runs where. It does not run your app (in a small setup). | nothing like it |
| **Worker node** | A "worker" computer. It runs your pods. | The machine running `docker run` |
| **Namespace** | A folder inside the cluster. Ours is `myapp`. | A Compose project name |
| **Pod** | The smallest thing that runs. It holds 1 container (here). It can die and be replaced. | One container |
| **Deployment** | A manager: "keep N pods of this alive". It replaces dead pods and updates versions. | A Compose service with `replicas` |
| **StatefulSet** | Like a Deployment, but for a database: fixed name and its own disk. | A service with a `volumes:` |
| **Service** | A fixed name + address in front of pods. Pods change; the Service does not. | A Compose service name (DNS) |
| **Ingress** | The front door from outside to Services. | `ports:` in Compose |
| **Job** | A pod that runs one task and stops (our migration). | `docker compose run ...` |

**Careful with the word "worker":**
- **Worker node** = a computer in the cluster.
- **Sidekiq worker** = a pod that runs background jobs (just our app's name for it).
They are totally different things.

---

## 2. The big picture (all layers)

```
+==============================================================================+
|  CLUSTER  (k3d / k3s on your laptop, or EKS in production)                   |
|                                                                              |
|  +------------------------+                                                  |
|  | CONTROL PLANE NODE     |   The boss. You talk to it with `kubectl`.       |
|  |  - API server          |   It stores what you WANT (your YAML files),     |
|  |  - Scheduler           |   and the scheduler picks a worker node          |
|  |  - Controllers         |   for every new pod.                             |
|  +-----------+------------+                                                  |
|              | orders: "run this pod on node 1", "keep 2 of these", ...      |
|     +--------+-----------------------------+                                 |
|     |                                      |                                 |
|     v                                      v                                 |
|  +--------------------------+   +--------------------------+                 |
|  | WORKER NODE 1            |   | WORKER NODE 2            |                 |
|  |  (a computer)            |   |  (a computer)            |                 |
|  |  kubelet = agent that    |   |  kubelet = agent that    |                 |
|  |  starts/stops containers |   |  starts/stops containers |                 |
|  |                          |   |                          |                 |
|  |   [ pods run here ]      |   |   [ pods run here ]      |                 |
|  +--------------------------+   +--------------------------+                 |
|                                                                              |
+==============================================================================+
```

On a local k3d cluster, each "node" is itself a Docker container on your laptop.
With one node, the control plane and the worker are the same computer.

---

## 3. What is INSIDE the namespace `myapp`

This is everything your YAML files create. Each box has its file name.

```
+-----------------------------------------------------------------------------+
| NAMESPACE: myapp                                    (k8s/00-namespace.yaml) |
|                                                                             |
|  SETTINGS (no pods, just data other pods read)                              |
|    ConfigMap  rails-config      (01-configmap.yaml)   RAILS_ENV, REDIS_URL..|
|    Secret     rails-secrets     (secrets.example)     DATABASE_URL, key     |
|    Secret     postgres-secrets  (secrets.example)     DB user / password    |
|                                                                             |
|  WORKLOADS (these make pods)                  SERVICE (fixed name)          |
|  ------------------------------------------  ---------------------------   |
|  Deployment  frontend    x2 pods (32)    <--  Service  frontend    :80       |
|  Deployment  rails-api   x2 pods (30)    <--  Service  rails-api   :80       |
|  Deployment  sidekiq     x1 pod  (31)         (no Service: nobody calls it)  |
|  Deployment  redis       x1 pod  (11)    <--  Service  redis       :6379     |
|  StatefulSet postgres    x1 pod  (10)    <--  Service  postgres    :5432     |
|        |                                       (headless = direct to pod)   |
|        +-- own disk (PVC) data-postgres-0, 5Gi, survives restarts           |
|                                                                             |
|  ONE-TIME TASK                                                              |
|    Job  rails-migrate    1 pod, runs `rails db:prepare`, then stops (20)    |
|                                                                             |
|  DOOR                                                                       |
|    Ingress  myapp  (40)   app.localhost -> Service frontend                 |
|                           api.localhost -> Service rails-api                |
|                                                                             |
|  EXTRAS FOR THE API                                                         |
|    HPA  rails-api (50)  keeps 2..6 pods, adds pods when CPU > 70%           |
|    PDB  rails-api (51)  during maintenance, never fewer than 1 API pod      |
+-----------------------------------------------------------------------------+

 Outside the namespace (installed by k3s/k3d, in namespace kube-system):
    Traefik = the "Ingress controller". It reads our Ingress rules and does the routing.
    metrics-server = gives CPU numbers to the HPA.
```

---

## 4. Where the PODS sit (on the worker nodes)

A Deployment says "I want 2 pods". The **scheduler** (control plane) chooses which worker node
gets each pod. The picture below is ONE possible result. You do not choose it, and it can change.

```
+--------------------- WORKER NODE 1 ---------------------+   +--------------------- WORKER NODE 2 ---------------------+
|                                                         |   |                                                         |
|  [pod] frontend-6d8f-aaa      (from Deployment frontend)|   |  [pod] frontend-6d8f-bbb      (from Deployment frontend)|
|  [pod] rails-api-7c9b-ccc     (from Deployment rails-api|   |  [pod] rails-api-7c9b-ddd     (from Deployment rails-api|
|  [pod] sidekiq-5f4a-eee       (from Deployment sidekiq) |   |  [pod] redis-8b2c-fff         (from Deployment redis)   |
|  [pod] postgres-0   + DISK data-postgres-0              |   |  [pod] rails-migrate-xxxxx    (Job: finished, Completed)|
|                                                         |   |                                                         |
+---------------------------------------------------------+   +---------------------------------------------------------+
```

Things to notice:
- Pod names have random endings (`-aaa`). When a pod dies, the new one gets a NEW name and a NEW IP.
  That is why Services exist.
- `postgres-0` has a fixed name (StatefulSet) and its disk follows it.
- The migration pod shows `Completed`. It did its job and stopped. It is not a problem.
- Total pods now: frontend 2 + rails-api 2 + sidekiq 1 + redis 1 + postgres 1 + migrate 1 = 8.
- If node 2 dies, the Deployments create replacement pods on node 1 by themselves.

---

## 5. How a user request travels (the web path)

```
   Browser: http://app.localhost:8080            Browser: http://api.localhost:8080
              |                                               |
              +------------------------+----------------------+
                                       v
                          +---------------------------+
                          | Traefik (Ingress controller)
                          | reads Ingress rules:      |
                          |  host app.* -> frontend   |
                          |  host api.* -> rails-api  |
                          +------+--------------+-----+
                                 |              |
                  host = app.localhost     host = api.localhost
                                 v              v
                      +----------------+  +-----------------+
                      | Service        |  | Service         |
                      | frontend :80   |  | rails-api :80   |
                      +---+--------+---+  +---+---------+---+
                          |        |          |         |        (Service picks a READY
                          v        v          v         v         pod; round robin)
                       [pod]    [pod]       [pod]     [pod]
                       nginx    nginx       Puma      Puma
                       (React files)        (Rails API, port 3000)
```

Step by step:
1. The browser asks for `app.localhost`. Traefik sees the host name and sends it to Service `frontend`.
2. The Service forwards to one of the 2 nginx pods. nginx returns the React files.
3. The React code runs in the browser and calls `http://api.localhost` (address baked in at image build time).
4. Traefik sends that to Service `rails-api`, which forwards to one of the 2 Puma pods.

Important: React runs in the **browser**, not in the cluster. So the frontend pod never calls the API pod.
The browser does, through the front door again.

---

## 6. How the pods talk INSIDE the cluster (the data path)

```
                       +-------------------+
   (from Traefik) ---> | rails-api pods x2 |
                       +----+---------+----+
                            |         |
        DATABASE_URL        |         |   REDIS_URL
        postgres://...@postgres:5432  |   redis://redis:6379/0
                            |         |
                            v         v
                   +----------+   +---------+
                   | Service  |   | Service |
                   | postgres |   | redis   |
                   +----+-----+   +----+----+
                        |              ^    ^
                        v              |    |  (1) rails-api PUSHES jobs in
                +---------------+      |    |
                | pod postgres-0|      |    +-- (2) sidekiq PULLS jobs out
                |  + disk 5Gi   |      |
                +---------------+   +--+----------+        sidekiq also uses
                        ^           | redis pod   |        DATABASE_URL to
                        |           +-------------+        read/write Postgres
                        |
          +-------------+--------------+
          | sidekiq pod  (no Service)  |-----> Service postgres (same as above)
          +----------------------------+
```

The names `postgres` and `redis` work like Compose service names. Kubernetes has a built-in DNS:
inside the namespace `myapp`, the short name `postgres` becomes the Service's address.

---

## 7. What happens when you run `kubectl apply -f k8s/`

```
 YOU                       CONTROL PLANE                            WORKER NODES
  |                              |                                       |
  | kubectl apply -f k8s/        |                                       |
  |----------------------------->| 1. API server saves your YAML         |
  |                              |    ("desired state")                  |
  |                              |                                       |
  |                              | 2. Namespace myapp is created (00)    |
  |                              | 3. ConfigMap is stored (01)           |
  |                              | 4. Postgres + Redis created (10, 11)  |
  |                              |                                       |
  |                              | 5. Controllers see "Deployment wants  |
  |                              |    2 pods" and create 2 pod objects   |
  |                              |                                       |
  |                              | 6. Scheduler picks a node for each -->| 7. kubelet on that node
  |                              |                                       |    pulls the image and
  |                              |                                       |    starts the container
  |                              |                                       |
  |                              |<--------------------------------------| 8. startup probe, then
  |                              |   9. When the readiness probe passes, |    readiness probe pass
  |                              |      the pod is added to its Service  |
  |                              |                                       |
  |                              | 10. HPA checks CPU every ~15s and     |
  |                              |     changes replicas (2..6)           |
```

Practical order (because the app needs the database first):
1. Create namespace, ConfigMap, Secrets.
2. Start Postgres and Redis. Wait until ready.
3. Run the Job `rails-migrate`. Wait until it is `Complete`.
4. Start rails-api, sidekiq and frontend.
5. Apply Ingress, HPA, PDB.

Only the Secrets are created by hand (`kubectl create secret ...`), because real passwords must not be saved in a file.

---

## 8. What Kubernetes does when something goes wrong

```
 Event                               Who reacts            Result
 ----------------------------------  --------------------  ----------------------------------
 A rails-api pod crashes             Deployment            Starts a new pod. Service skips the
                                                           dead one meanwhile. Users see nothing.
 A pod is stuck (liveness fails)     kubelet               Restarts the container.
 A pod is not ready yet               Service              Sends no traffic to it until ready.
 A worker node dies                  Controllers+Scheduler Pods are re-created on another node.
 CPU goes above 70% on the API       HPA                   Adds pods (max 6).
 You deploy image 1.0.1              Deployment            Rolling update: +1 new pod, wait
                                                           ready, -1 old pod, repeat. No downtime.
 Admin drains a node                 PDB                   Keeps at least 1 API pod running.
 postgres-0 is deleted               StatefulSet           New postgres-0 starts, same disk,
                                                           data is kept.
```

---

## 9. Handy commands to SEE this diagram on your own cluster

These only read information. They change nothing.

```
kubectl get nodes                     # the nodes (control plane + workers)
kubectl get ns                        # namespaces
kubectl -n myapp get all              # deployments, pods, services in myapp
kubectl -n myapp get pods -o wide     # also shows WHICH node each pod is on
kubectl -n myapp get ingress          # the front door rules
kubectl -n myapp get pvc              # the Postgres disk
kubectl -n myapp describe pod <name>  # why a pod is not starting
kubectl -n myapp logs deploy/rails-api
```

`get pods -o wide` is the real version of the picture in section 4.

---

## 10. One-page summary

```
 Browser -> Traefik (Ingress) -> Service -> Pods (made by a Deployment) -> run on Worker Nodes
                                                 |
                                                 +-> Service postgres -> pod postgres-0 -> disk
                                                 +-> Service redis    -> pod redis  <- sidekiq pod
 Control plane = decides.   Worker nodes = run.   Namespace myapp = the folder holding it all.
```
