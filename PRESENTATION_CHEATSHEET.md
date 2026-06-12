# Presentation Cheat Sheet - Trình Bày Cho Mentor

## 📊 Cách Trình Bày (Timeline 15 Phút)

### **Slide 1: Mở Đầu (1 phút)**
```
Tiêu đề: W9 GitOps Lab - Canary Deployment + Auto-Alerting

Nội dung:
- Dự án: Deploy Flask API an toàn sử dụng Canary + GitOps
- Mục đích: Giảm rủi ro deploy, monitoring tự động, alert email khi có sự cố
- Tech: Kubernetes, ArgoCD, Prometheus, Argo Rollouts

Câu mở: "Tôi sẽ giải thích kiến trúc, cách hoạt động, và kết quả đã đạt được"
```

---

### **Slide 2: Vấn Đề & Giải Pháp (2 phút)**

**Vấn Đề:**
```
Traditional Deploy (All-at-once):
  v1 (100% users) → STOP → v2 (100% users)
  
Nếu v2 có BUG:
  ❌ 100% users bị impact
  ❌ Phải thủ công rollback
  ❌ Mất tiền & reputation
```

**Giải Pháp: Canary Deployment**
```
Step 1: Deploy to 5% users
  v1 (95% users) + v2 (5% users)
  → Monitor metrics (success-rate, error-rate)
  
Step 2-4: Gradually increase (10% → 50% → 100%)
  → Tại mỗi step, verify metrics
  
Result:
  ✅ Nếu metrics tốt → 100% users dùng v2
  ⚠️ Nếu metrics xấu → Tự động rollback (không bao giờ 100%)
  
Lợi ích: Phát hiện bug sớm, tỷ lệ bị ảnh hưởng < 5%, tự động rollback
```

---

### **Slide 3: Architecture (3 phút)**

**Draw on whiteboard hoặc show diagram:**
```
┌─────────────┐
│ Git Repo    │ ← Toàn bộ YAML manifests lưu đây
│ (GitHub)    │
└──────┬──────┘
       │ (pull every 3 min)
       ↓
┌─────────────────────────────────────────┐
│ ArgoCD Controller                       │
│ (GitOps Controller)                     │
│ - Compare Git state vs Cluster state    │
│ - Apply diffs tự động                   │
└──────┬──────────────────────────────────┘
       │ (kubectl apply)
       ↓
┌─────────────────────────────────────────┐
│ Kubernetes Cluster                      │
│ ├─ demo namespace                       │
│ │  └─ Rollout api (Canary + Analysis)  │
│ ├─ monitoring namespace                 │
│ │  ├─ Prometheus (scrape metrics)       │
│ │  └─ Alertmanager (gửi email)          │
│ └─ argocd namespace                     │
│    └─ ArgoCD server                     │
└──────┬──────────────────────────────────┘
       │
       ├─→ Prometheus    ← Flask app exposes /metrics
       ├─→ Alertmanager  ← Prometheus fires alerts
       └─→ SMTP Server   ← Email to tp17112k4@gmail.com
```

**Giải thích từng bộ phận:**
- **Git**: Single source of truth (toàn bộ infra as code)
- **ArgoCD**: Automated deployment (GitOps principle)
- **Kubernetes**: Container orchestration
- **Prometheus**: Metrics collection & alerting
- **Alertmanager**: Email delivery

---

### **Slide 4: Canary Workflow (3 phút)**

**Show real-time trên cluster (nếu có thể) hoặc mock:**

```bash
# COMMAND 1: Kiểm tra Rollout status
kubectl get rollout api -n demo -o wide

# Expected output:
# NAME   DESIRED   CURRENT   UP-TO-DATE   READY   AGE
# api    1         1         1            1       2h
```

```
Giải thích khi chạy:
- DESIRED: Mong muốn 1 replica
- CURRENT: Hiện tại có 1 replica
- READY: 1 replica ready (passed health check)
→ Kết luận: Rollout Healthy ✅
```

**Workflow cụ thể:**
```
1️⃣ Bạn push code k8s-api/api.yaml (YAML manifest chứa Rollout + env)
   git add . && git commit -m "..." && git push origin main

2️⃣ ArgoCD detect (mỗi 3 phút):
   kubectl -n argocd get applications api
   → status: OutOfSync (Git != Cluster)

3️⃣ ArgoCD apply changes:
   kubectl apply -f k8s-api/api.yaml
   → Kubernetes tạo Rollout mới

4️⃣ Argo Rollouts canary deploy:
   Stable:  v2 (100%)        Current progress: 0%
   Canary:  v3 (0%)
       ↓ 10 sec setup
   Stable:  v2 (95%)         Current progress: 5%
   Canary:  v3 (5%)
       ↓ Prometheus monitor success-rate...
       ↓ 10 minutes wait
   Stable:  v2 (90%)         Current progress: 10%
   Canary:  v3 (10%)
       ↓ ... (more steps)
   Stable:  v3 (100%)        Current progress: 100% ✅

5️⃣ Prometheus analyze (at each step):
   Query: success_rate = requests_ok / requests_total
   Result: 0.95 (95% success)
   Condition: result >= 0.8? YES ✅
   Action: Continue to next step

   Nếu result < 0.8:
   → Rollout abort (stop at 5%, never reach 100%)
   → Rollback to v2 (previous version)
```

---

### **Slide 5: Metrics & Alerting (2 phút)**

**Prometheus Query:**
```
flask_http_request_total metric:
  total requests = 1000
  success (2xx, 3xx) = 950
  errors (4xx, 5xx) = 50
  
Success rate = 950 / 1000 = 0.95 (95%)

Canary success condition:
  success_rate >= 0.8 → PASS ✅
  success_rate < 0.8  → FAIL ❌ (abort & rollback)
```

**Alert Triggering:**
```
PrometheusRule test-email-alert:
  Condition: vector(1) = 1 (always true)
  Interval: Evaluated every 15 seconds
  
Nếu condition true → Alert fires
  → Alertmanager receives alert
  → Routing rules: to: "email"
  → SMTP config (username: xxx@gmail.com, password: from Secret)
  → Email sent to tp17112k4@gmail.com
  
Email sẽ chứa:
  Subject: [FIRING] FireTest
  Body: Alert: FireTest
        Instance: prometheus-<pod>
        Severity: warning
        Value: 1
```

---

### **Slide 6: Code Deep Dive (2 phút)**

**Show files on screen:**

#### **File 1: k8s-api/api.yaml (Rollout definition)**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: api
  namespace: demo
spec:
  # Replicas
  replicas: 1
  
  # Canary strategy
  strategy:
    canary:
      steps:
        - setWeight: 5
        - pause:
            duration: 10m
        - setWeight: 10
        - pause:
            duration: 5m
        - setWeight: 20
        - pause:
            duration: 5m
      # ← Tới đây, nếu analysis pass → 100%, không cần step nữa
      analysis:
        templates:
          - name: api-success-rate  # ← Xem analysis.yaml
            requiredForProgression: true  # Phải pass thì mới continue
  
  # Template
  spec:
    containers:
      - name: api
        image: gcr.io/.../api:latest
        ports:
          - containerPort: 5000
        env:
          - name: ERROR_RATE
            value: "0"          # ← Không inject errors (0% = production)
          - name: VERSION       
            value: "v3"         # ← Version tag
```

**Giải thích:**
- `setWeight: 5` → 5% traffic to canary
- `pause: 10m` → Chờ 10 phút, verify metrics
- `requiredForProgression: true` → Phải pass analysis mới tiếp tục

---

#### **File 2: k8s-api/analysis.yaml (Success criteria)**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: api-success-rate
spec:
  metrics:
    - name: success-rate
      interval: 1m           # Query mỗi 1 phút
      count: 10              # Kiểm tra 10 lần (10 phút tổng)
      provider:
        prometheus:
          address: http://prometheus:9090
          query: |
            sum(rate(flask_http_request_total{status=~"2.*|3.*"}[5m])) /
            sum(rate(flask_http_request_total[5m]))
      
      # Success/Fail criteria
      successCriteria: result[0] >= 0.8    # >= 80% success
      failureLimit: 1                       # Fail 1 time → abort
      
      # Optional: warning threshold
      inconclusiveLimit: 3                  # Inconclusive 3 times → abort
```

**Giải thích Prometheus query:**
```
Numerator: sum(rate(flask_http_request_total{status=~"2.*|3.*"}[5m]))
  = Tổng requests với status 2xx hoặc 3xx (success)
  = Tính rate (requests/sec) trong 5 phút cuối cùng

Denominator: sum(rate(flask_http_request_total[5m]))
  = Tổng tất cả requests (rate)

Result: numerator / denominator = success_rate (0-1)
```

---

#### **File 3: argocd/apps/api.yaml (GitOps sync)**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: api
  namespace: argocd
spec:
  project: default
  
  source:
    repoURL: https://github.com/TIEUPHUONG1711/w9_lab.git
    targetRevision: HEAD        # ← Main branch
    path: k8s-api               # ← Sync từ folder k8s-api/
  
  destination:
    server: https://kubernetes.default.svc  # ← Local cluster
    namespace: demo             # ← Apply vào namespace demo
  
  syncPolicy:
    automated:
      prune: true              # ← Xóa resource nếu không trong Git
      selfHeal: true           # ← Auto-sync nếu cluster drift
    syncOptions:
      - CreateNamespace=true
```

**Giải thích:**
- `repoURL + path: k8s-api` → ArgoCD pull từ https://github.com/.../k8s-api
- `automated.prune` → Nếu xóa file từ Git → Kubernetes resource bị xóa
- `selfHeal` → Nếu ai đó manually delete pod → ArgoCD sẽ recreate

---

#### **File 4: argocd/apps/kube-prometheus-stack.yaml (Email config)**
```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: kube-prometheus-stack
spec:
  source:
    chart: kube-prometheus-stack
    repoURL: https://prometheus-community.github.io/helm-charts
    targetRevision: 55.0.0
    helm:
      values: |
        prometheus:
          prometheusSpec:
            retention: 7d
            storageSpec:
              volumeClaimTemplate:
                spec:
                  accessModes: ["ReadWriteOnce"]
                  resources:
                    requests:
                      storage: 10Gi
        
        alertmanager:
          enabled: true
          config:
            global:
              resolve_timeout: 5m
              # ← SMTP config tương tự ở đây
            receivers:
              - name: email
                email_configs:
                  - to: tp17112k4@gmail.com
                    from: notification@lab.example.com
                    smarthost: smtp.gmail.com:587
                    auth_username: xxx@gmail.com
                    auth_password: <base64-encoded>  # ← Từ Secret
                    headers:
                      Subject: '[{{ .GroupLabels.alertname }}] Alert'
            route:
              receiver: email
              group_by: ['alertname']
              group_wait: 30s
              group_interval: 5m
              repeat_interval: 4h
```

**Giải thích:**
- `receivers.email_configs.to` → Recipient email
- `auth_password` → SMTP password (từ alertmanager-smtp-secret.yaml)
- `route.receiver: email` → All alerts route to email

---

### **Slide 7: Current Status (1 phút)**

**Run commands & show results:**

```bash
# Command 1: Rollout status
kubectl get rollout -n demo -o wide
kubectl get rollout api -n demo -o jsonpath='{.status.phase}'

# Expected: "Healthy"
```

```bash
# Command 2: ArgoCD Applications status
kubectl get applications -n argocd
kubectl get application api -n argocd -o jsonpath='{.status.sync.status} {.status.health.status}'
kubectl get application kube-prometheus-stack -n argocd -o jsonpath='{.status.sync.status} {.status.health.status}'

# Expected: "Synced Healthy"
```

```bash
# Command 3: Prometheus targets (data sources)
kubectl get prometheus -n monitoring
kubectl get servicemonitor -n demo

# Expected: servicemonitor/api exists (tells Prometheus to scrape Flask app)
```

```bash
# Command 4: Alertmanager + email config
kubectl get secret alertmanager-smtp-secret -n monitoring
kubectl get prometheusrule -n monitoring

# Expected: Both exist
```

**Summary:**
```
✅ Rollout api: Healthy
✅ ArgoCD Applications: Synced Healthy
✅ Prometheus: Collecting metrics
✅ Alertmanager: Ready to send emails
✅ Secret: SMTP credentials deployed
✅ Test Alert Rule: Ready to fire
```

---

## 🎤 Q&A Expected Questions & Answers

### **Q1: "Tại sao lại cần canary deployment?"**

**Answer (30 seconds):**
> "Canary giúp giảm rủi ro deploy. Thay vì 100% users dùng version mới lúc đầu, chúng ta chỉ cho 5% users dùng trước. Nếu có bug, phát hiện sớm → tự động rollback (không bao giờ reach 100% traffic). Nếu metrics tốt, ta tăng dần (10% → 20% → 100%) trên 20 phút.
> 
> Benefit: Phát hiện bug sớm, tỷ lệ user bị ảnh hưởng < 5%, tự động rollback (không cần thủ công)"

---

### **Q2: "ArgoCD vs kubectl apply - cái nào tốt hơn?"**

**Answer (30 seconds):**
> "ArgoCD (GitOps) tốt hơn:
> - **kubectl apply**: Manual, dễ mắc lỗi, khó audit
> - **ArgoCD**: Git là single source of truth, tự động sync, dễ rollback (revert commit), full audit trail
> 
> Ngoài ra, ArgoCD tự động prune resources (nếu xóa từ Git → cluster sẽ xóa), và selfHeal (nếu ai đó manually delete pod → ArgoCD recreate)"

---

### **Q3: "Prometheus scrape metrics từ đâu?"**

**Answer (30 seconds):**
> "Flask app expose `/metrics` endpoint (using flask_prometheus library).
> 
> Prometheus mỗi 15 giây:
> 1. Scrape: GET http://api:5000/metrics
> 2. Parse response: flask_http_request_total, flask_http_request_duration, etc.
> 3. Store: Time-series database
> 4. Evaluate rules: Alerting rules (nếu success_rate < 0.8 → fire alert)
>
> ServiceMonitor Kubernetes resource (k8s-api/servicemonitor.yaml) báo cho Prometheus biết endpoint nào để scrape"

---

### **Q4: "Nếu secret SMTP bị lộ thì sao?"**

**Answer (1 minute):**
> "Hiện tại, password được base64 encode vào Secret (k8s-api/monitoring/alertmanager-smtp-secret.yaml) và commit vào Git.
> 
> Base64 KHÔNG phải encryption (dễ decode) → Không hoàn toàn secure.
> 
> Giải pháp tốt hơn:
> 1. **SealedSecret**: Dùng kubeseal, mã hóa Secret → chỉ cluster có thể decrypt
> 2. **ExternalSecret**: Fetch password từ AWS Secrets Manager / Vault
> 3. **ArgoCD Notifications**: Built-in notification system (không cần store password)
>
> Trong lab này, cách 1 là đủ (production: dùng cách 2 hoặc 3)"

---

### **Q5: "Làm sao để biết alert đã gửi email không?"**

**Answer (30 seconds):**
> "Check Alertmanager logs:
> ```bash
> kubectl logs -n monitoring -l app.kubernetes.io/name=alertmanager -f
> ```
>
> Tìm dòng: 'notifier=email' hoặc 'level=info' (nếu SMTP send successfully).
>
> Ngoài ra, có thể check:
> - Alertmanager UI: http://localhost:9093 (port-forward)
> - Gmail spam folder (email có thể bị filter)"

---

### **Q6: "Failure limit = 1 có nghĩa là gì?"**

**Answer (30 seconds):**
> "AnalysisTemplate `failureLimit: 1` có nghĩa:
> - Nếu success_rate < 0.8 lần đầu tiên → Fail (counter = 1)
> - Nếu counter > failureLimit → Abort canary & rollback
>
> Với failureLimit = 1, chỉ cần fail 1 lần → abort.
>
> Nếu set failureLimit = 3, ta cho phép fail 3 lần trước abort.
>
> Mục đích: Tránh false positive (metric tạm thời xấu, nhưng không phải bug)"

---

### **Q7: "Làm sao để trigger alert manually?"**

**Answer (1 minute):**
> "Alert được trigger tự động:
> - Prometheus evaluate alert rules mỗi 15 giây
> - Nếu condition true → Alert fires
>
> Test alert rule (prometheusrule-test-alert.yaml):
> ```yaml
> alert: FireTest
> expr: vector(1)  # Always true (1 = always fire)
> ```
>
> Để trigger:
> 1. Check nếu rule đã deployed: `kubectl get prometheusrule -n monitoring`
> 2. Check Prometheus UI: http://localhost:9090 → Alerts tab
> 3. Verify status 'FIRING' (sau 15 sec)
> 4. Check Alertmanager UI: http://localhost:9093 → Alerts tab
> 5. Check email: Monitor Alertmanager logs hoặc check Gmail inbox
>
> Nếu muốn trigger khác:
> - Modify analysis.yaml query → make result < 0.8
> - Trigger: Set ERROR_RATE=0.5 trong k8s-api/api.yaml"

---

## 🔧 Demo Commands (Copy-Paste)

```bash
# ========== CHECK ROLLOUT ==========
kubectl get rollout api -n demo -o wide
kubectl get rollout api -n demo -o jsonpath='{.status.phase}'
kubectl describe rollout api -n demo

# ========== CHECK ARGOCD ==========
kubectl get applications -n argocd
kubectl get application api -n argocd -o jsonpath='{.status.sync.status} {.status.health.status}'
kubectl get application kube-prometheus-stack -n argocd -o jsonpath='{.status.sync.status} {.status.health.status}'

# ========== CHECK PROMETHEUS ==========
kubectl get prometheus -n monitoring
kubectl get servicemonitor -n demo
kubectl port-forward -n monitoring svc/kube-prometheus-stack-prometheus 9090:9090
# Rồi mở http://localhost:9090/graph → query: flask_http_request_total

# ========== CHECK ALERTMANAGER ==========
kubectl get secret alertmanager-smtp-secret -n monitoring
kubectl get prometheusrule -n monitoring
kubectl port-forward -n monitoring svc/kube-prometheus-stack-alertmanager 9093:9093
# Rồi mở http://localhost:9093

# ========== CHECK LOGS ==========
kubectl logs -n monitoring -l app.kubernetes.io/name=alertmanager -f
kubectl logs -n demo -l app=api -f

# ========== CHECK ANALYSIS RUNS ==========
kubectl get analysisrun -n demo
kubectl describe analysisrun <name> -n demo

# ========== FORCE ARGOCD SYNC ==========
kubectl -n argocd annotate application api argocd.argoproj.io/refresh=hard --overwrite
```

---

## 📋 Presentation Checklist

- [ ] **Intro (1 min)**: Giải thích mục đích project
- [ ] **Problem (1 min)**: Tại sao cần canary?
- [ ] **Architecture (2 min)**: Draw 5 layers, giải thích từng bộ phận
- [ ] **Workflow (2 min)**: Canary steps, Prometheus analysis, metric evaluation
- [ ] **Code Deep Dive (2 min)**: Show k8s-api/api.yaml, analysis.yaml, argocd/apps/
- [ ] **Status Check (1 min)**: Run 3-4 commands, show ✅ status
- [ ] **Q&A (5 min)**: Prepared answers
- [ ] **Demo (optional)**: Port-forward Prometheus/Alertmanager, show UI

---

## 💡 Tips Trình Bày

1. **Bắt đầu bằng "why"**: Tại sao lại dùng canary? Tại sao GitOps? Đừng vào kỹ thuật ngay
2. **Draw trước khi code**: Whiteboard architecture trước, rồi mới show code
3. **Đơn giản hóa**: Đừng explain toàn bộ Prometheus query, chỉ nói "nó tính success-rate"
4. **Live demo tốt hơn slides**: Nếu có thể, run command live (port-forward Prometheus, show metrics)
5. **Kết nối benefits**: "Canary tự động rollback, không cần thủ công, giảm downtime"
6. **Chuẩn bị backup**: Nếu live demo fail, có sẵn screenshots
7. **Confident answers**: Không biết → "Tôi sẽ tìm hiểu thêm" (tốt hơn nói sai)
8. **Eye contact & tone**: Nói chậm, nói rõ, eye contact với mentor
