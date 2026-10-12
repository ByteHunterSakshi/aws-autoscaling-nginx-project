# Highly Available Web Hosting on AWS with Auto Scaling, NAT Gateway and Ubuntu (Nginx)

A hands-on cloud project where I built a **self-healing, auto-scaling web hosting environment on AWS**. Ubuntu EC2 instances are launched automatically by an **Auto Scaling Group** from a **Launch Template**, configure themselves on first boot using **EC2 user data**, and serve different pages (an **Nginx web page** and a **Database page**) across **public and private subnets** inside a custom **VPC**. Private instances reach the internet safely through a **NAT Gateway**.

> **Region:** US East (N. Virginia) `us-east-1`  |  **OS:** Ubuntu (Linux)  |  **Web server:** Nginx  |  **Instance type:** t3.micro

---

## Table of contents

1. [Project overview](#1-project-overview)
2. [Architecture diagram](#2-architecture-diagram)
3. [Final outcome](#3-final-outcome)
4. [AWS services used and what each one does](#4-aws-services-used-and-what-each-one-does)
5. [How the traffic flows](#5-how-the-traffic-flows)
6. [Linux concepts used](#6-linux-concepts-used)
7. [Step-by-step implementation](#7-step-by-step-implementation)
8. [User data script](#8-user-data-script)
9. [How to verify everything works](#9-how-to-verify-everything-works)
10. [Problems I faced and how I fixed them](#10-problems-i-faced-and-how-i-fixed-them)
11. [Security notes](#11-security-notes)
12. [Possible improvements](#12-possible-improvements)
13. [Cost and cleanup](#13-cost-and-cleanup)
14. [What I learned](#14-what-i-learned)
15. [Author](#15-author)

---

## 1. Project overview

**Goal:** Host a website on AWS in a way that is automated, repeatable and resilient, without logging in to a server and installing software by hand.

**What I built:**

- A custom **VPC** with **2 public subnets** and **1 private subnet**.
- An **Internet Gateway** so public subnets can talk to the internet.
- A **NAT Gateway** (with an Elastic IP) so the private subnet can download updates and packages without being exposed to the internet.
- A **Security Group** that controls which traffic is allowed in.
- A **Launch Template** that stores the instance blueprint (Ubuntu AMI, t3.micro, security group, user data).
- An **Auto Scaling Group (ASG)** that launches and replaces EC2 instances automatically from that template.
- **User data (a Bash script)** that installs Nginx and creates a styled web page on first boot.
- Different instances serving different pages: an **Nginx web page** in the public subnet and a **Database page** in the private subnet.

**Why this matters:** If an instance crashes or is terminated, the ASG detects it and launches a fresh one with the exact same configuration. No manual work is needed.

---

## 2. Architecture diagram

**Architecture summary**

| Layer | Component |
|---|---|
| Entry point | User browser, Internet Gateway |
| Network | VPC, 2 public subnets, 1 private subnet, route tables |
| Outbound access for private subnet | NAT Gateway with Elastic IP |
| Compute | EC2 Ubuntu instances (Nginx web server, Database server) |
| Automation | Launch Template, Auto Scaling Group |
| Security | Security Group |
| Operating system | Linux (Ubuntu) |

---

## 3. Final outcome

After the Auto Scaling Group launched the instances, opening the public IP of a web instance in the browser (`http://<public-ip>`) showed a styled page titled **"Hello from AWS Auto Scaling!"**, built entirely by the user data script.

The page shows live details pulled from the instance itself:

- **Instance ID** (for example `i-06259d57d0db8da61`)
- **Availability Zone** (for example `us-east-1a`)
- **Private IP** (for example `10.0.1.104`)
- **Web server:** Nginx on Ubuntu

This proves that the Launch Template, user data, networking and Auto Scaling Group all worked together correctly.

The EC2 console also shows the Auto Scaling Group's **self-healing** behavior: older instances in the `Terminated` state and the newest instance `Running` with `3/3 checks passed`.

---

## 4. AWS services used and what each one does

### 4.1 Amazon VPC (Virtual Private Cloud)

**What it is:** Your own isolated, private network inside AWS.

**What happens in this project:** I created a custom VPC with an IP range (for example `10.0.0.0/16`). Every resource (subnets, EC2 instances, NAT Gateway) lives inside it. This gives full control over IP ranges, routing and security instead of using the default VPC.

### 4.2 Subnets (2 public, 1 private)

**What it is:** A subnet is a smaller slice of the VPC's IP range that lives in one Availability Zone.

| Subnet | Purpose | Has public IP? | Route to internet |
|---|---|---|---|
| Public subnet 1 | Hosts the Nginx web server | Yes (auto-assign public IP enabled) | `0.0.0.0/0` to Internet Gateway |
| Public subnet 2 | Hosts the NAT Gateway | NAT uses an Elastic IP | `0.0.0.0/0` to Internet Gateway |
| Private subnet | Hosts the database server | No | `0.0.0.0/0` to NAT Gateway |

**Key idea:** A subnet is "public" or "private" only because of its **route table**, not its name. A subnet is public when its route table sends internet traffic to an Internet Gateway.

### 4.3 Route tables

**What it is:** A set of rules that decides where network traffic goes.

**What happens in this project:**

- **Public route table:** `10.0.0.0/16 -> local` and `0.0.0.0/0 -> Internet Gateway`
- **Private route table:** `10.0.0.0/16 -> local` and `0.0.0.0/0 -> NAT Gateway`

Each route table is associated with the right subnets in the **Subnet associations** tab.

### 4.4 Internet Gateway (IGW)

**What it is:** The door between the VPC and the public internet. It is highly available and managed by AWS.

**What happens in this project:** It allows users' browsers to reach the web instances in the public subnets, and it allows those instances to send replies back. It also carries the NAT Gateway's outbound traffic to the internet.

### 4.5 NAT Gateway and Elastic IP

**What it is:** A managed service that lets instances in a **private** subnet start connections to the internet, while blocking the internet from starting connections to them. An **Elastic IP** is the fixed public IPv4 address assigned to the NAT Gateway.

**What happens in this project:**

1. The private instance wants to run `apt-get update` or download packages.
2. Its route table sends `0.0.0.0/0` to the NAT Gateway.
3. The NAT Gateway (placed in a **public** subnet) forwards the request to the Internet Gateway using its Elastic IP.
4. The response comes back through the NAT Gateway to the private instance.

**Result:** The private instance can download updates but is **not reachable from the internet**. This is a standard security pattern for databases and backend servers.

### 4.6 Security Group

**What it is:** A virtual firewall attached to EC2 instances. It is stateful: if a request is allowed in, the response is automatically allowed out.

**Inbound rules used:**

| Type | Port | Source | Why |
|---|---|---|---|
| HTTP | 80 | `0.0.0.0/0` | Let browsers load the web page |
| SSH | 22 | My IP / EC2 Instance Connect range | Connect to the instance for administration |

### 4.7 Amazon EC2 (Elastic Compute Cloud)

**What it is:** Virtual servers in the cloud.

**What happens in this project:** Each instance is a `t3.micro` running **Ubuntu**. Instances in the public subnet run **Nginx** and serve the web page. The instance in the private subnet acts as the database server and serves the database page. Each instance has an **EBS volume** (its root disk). When the ASG terminates an instance, its volume is deleted too, which is why the console sometimes shows "volume does not exist" for old instances.

### 4.8 AMI (Amazon Machine Image)

**What it is:** The template of the operating system and base software used to start an instance.

**What happens in this project:** I used an **Ubuntu** AMI. This matters because package names and commands differ between Linux distributions (Ubuntu uses `apt`, Amazon Linux uses `dnf/yum`).

### 4.9 Launch Template

**What it is:** A saved blueprint that tells AWS exactly how to build an instance.

**It stores:**

- AMI (Ubuntu)
- Instance type (`t3.micro`)
- Key pair
- Security group
- Network settings (auto-assign public IP for public instances)
- **User data script**

**Important:** Every edit creates a **new version**. The Auto Scaling Group must be set to use `Latest` (or the new version number), otherwise it keeps launching instances with the old script.

### 4.10 EC2 User data

**What it is:** A script that runs **once, as root, on the first boot** of an instance.

**What happens in this project:** The script updates the package list, installs Nginx, starts and enables it, reads the instance's own metadata (Instance ID, Availability Zone, Private IP) from the **Instance Metadata Service (IMDSv2)**, and writes a styled `index.html` page. This is how every new instance configures itself automatically with zero manual steps.

### 4.11 Amazon EC2 Auto Scaling Group (ASG)

**What it is:** A service that keeps the right number of healthy EC2 instances running.

**What happens in this project:**

- **Desired / Minimum / Maximum capacity** define how many instances should run.
- The ASG launches instances from the **Launch Template** across the selected subnets and balances them across Availability Zones.
- It runs **health checks**. If an instance is unhealthy or terminated, the ASG **terminates it and launches a replacement** automatically (self-healing).
- The **Activity** tab shows every `Launching` and `Terminating` event with the reason.

This is why the console shows many `Terminated` instances and one `Running` instance: it is the ASG replacing instances while I fixed the user data.

### 4.12 EC2 Instance Connect (SSH access)

**What it is:** A browser-based way to open a terminal on an instance without managing SSH keys manually.

**What happens in this project:** I used it to log in to instances and debug user data using commands like `systemctl status` and reading `/var/log/cloud-init-output.log`.

### 4.13 Amazon CloudWatch (used behind the scenes)

**What it is:** AWS's monitoring service.

**What happens in this project:** Auto Scaling publishes metrics to CloudWatch, and EC2 status checks (`3/3 checks passed`) come from it. CloudWatch alarms can be used later to trigger scale-out and scale-in policies.

---

## 5. How the traffic flows

### 5.1 A user opens the website (inbound)

1. The user types `http://<public-ip>` in the browser.
2. The request reaches the **Internet Gateway**.
3. The public route table sends it to the **EC2 instance** in the public subnet.
4. The **Security Group** checks that port 80 is allowed.
5. **Nginx** returns `index.html`.
6. The response goes back through the Internet Gateway to the browser.

### 5.2 A private instance downloads updates (outbound only)

1. The private instance sends a request to the internet.
2. The private route table sends `0.0.0.0/0` to the **NAT Gateway**.
3. The NAT Gateway (in a public subnet) forwards it via the **Internet Gateway** using its **Elastic IP**.
4. The reply returns the same way.
5. Nobody on the internet can start a connection to the private instance.

### 5.3 An instance is created (automation)

1. The **Auto Scaling Group** notices fewer healthy instances than desired.
2. It reads the **Launch Template**.
3. It launches a new **EC2 instance** in the chosen subnet.
4. On first boot, **user data** installs Nginx and builds the web page.
5. The instance passes status checks and starts serving traffic.

---

## 6. Linux concepts used

| Concept | Command / location | Used for |
|---|---|---|
| Package manager (Ubuntu) | `apt-get update`, `apt-get install -y nginx` | Installing the web server |
| Service management | `systemctl enable --now nginx`, `systemctl status nginx` | Starting Nginx and keeping it running after reboot |
| Web root | `/var/www/html/index.html` | The page Nginx serves |
| Boot logs | `/var/log/cloud-init-output.log` | Debugging user data |
| Metadata service | `curl http://169.254.169.254/latest/meta-data/` | Reading Instance ID, AZ and Private IP |
| Heredoc and `sed` | `cat > file <<'EOF'`, `sed -i` | Writing the HTML page and filling in values |
| Root privileges | `sudo` | Running administrative commands |

---

## 7. Step-by-step implementation

1. **Create the VPC** with a CIDR block such as `10.0.0.0/16`.
2. **Create 3 subnets:** two public and one private, ideally in different Availability Zones.
3. **Create and attach an Internet Gateway** to the VPC.
4. **Create a public route table:** add `0.0.0.0/0 -> Internet Gateway`, associate it with both public subnets, and enable **auto-assign public IPv4** on those subnets.
5. **Allocate an Elastic IP** and **create a NAT Gateway** in a public subnet using that Elastic IP.
6. **Create a private route table:** add `0.0.0.0/0 -> NAT Gateway` and associate it with the private subnet.
7. **Create a Security Group:** allow HTTP 80 and SSH 22 inbound.
8. **Create a Launch Template:** Ubuntu AMI, `t3.micro`, key pair, security group, and paste the user data script.
9. **Create the Auto Scaling Group:** choose the Launch Template, select the subnets, set desired/min/max capacity, and enable health checks.
10. **Wait 2-3 minutes** for the instance to boot and run user data.
11. **Open `http://<public-ip>`** in the browser and confirm the page loads.

---

## 8. User data script

Pasted into **Launch Template -> Advanced details -> User data** (the first line must be exactly `#!/bin/bash`):

```bash
#!/bin/bash
apt-get update -y
apt-get install -y nginx
systemctl enable --now nginx

# Read instance details using IMDSv2
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/local-ipv4)

# Write a styled HTML page, then fill in the instance values
cat > /var/www/html/index.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><title>AWS Auto Scaling Demo</title></head>
<body>
  <h1>Hello from AWS Auto Scaling!</h1>
  <p>Instance ID: __INSTANCE_ID__</p>
  <p>Availability Zone: __AZ__</p>
  <p>Private IP: __PRIVATE_IP__</p>
  <p>Web Server: Nginx on Ubuntu</p>
</body>
</html>
EOF

sed -i "s/__INSTANCE_ID__/$INSTANCE_ID/; s/__AZ__/$AZ/; s/__PRIVATE_IP__/$PRIVATE_IP/" /var/www/html/index.html
```

The full, styled version of the page (gradient background, glass card, animated rocket) is in [`userdata-ubuntu-nginx.sh`](userdata-ubuntu-nginx.sh).

**What each part does**

- `apt-get update` and `install nginx`: installs the web server.
- `systemctl enable --now nginx`: starts Nginx now and on every reboot.
- IMDSv2 `TOKEN` call: gets a session token, then reads metadata securely.
- `cat > index.html <<'EOF'`: writes the page. Quoted `'EOF'` prevents the shell from changing the HTML.
- `sed -i`: replaces the placeholders with real instance values.

---

## 9. How to verify everything works

Connect with **EC2 Instance Connect** and run:

```bash
# Was the user data attached?
curl -s http://169.254.169.254/latest/user-data | head -5

# Did user data run without errors?
sudo tail -50 /var/log/cloud-init-output.log

# Is Nginx running?
sudo systemctl status nginx

# Does the server answer locally?
curl -I http://localhost
```

Then open `http://<public-ip>` in the browser (use **http**, not https).

From the **private** instance, confirm NAT works:

```bash
curl -I https://archive.ubuntu.com    # should respond through the NAT Gateway
```

---

## 10. Problems I faced and how I fixed them

| # | Problem | Cause | Fix |
|---|---|---|---|
| 1 | Browser showed **"refused to connect"** | Nothing was listening on port 80 because the web server never installed | Checked logs inside the instance and fixed user data |
| 2 | `Unit httpd.service could not be found` | I used an **Amazon Linux** script (`dnf`, `httpd`) on an **Ubuntu** AMI | Rewrote the script with `apt-get` and `nginx` |
| 3 | New script did not apply | Auto Scaling Group was using an **old Launch Template version** | Set the ASG to `Latest` version and terminated old instances so new ones launched |
| 4 | Private instance could not install packages | No route to the internet | Added a **NAT Gateway** and the `0.0.0.0/0 -> NAT` route |
| 5 | Page not reachable on public IP | Browser tried `https://` (port 443 is closed) | Used `http://` explicitly |
| 6 | "Failed to describe volume ... does not exist" in console | The ASG had terminated an old instance and its EBS volume was already deleted | Refreshed the console; it is only a display issue, not a project error |
| 7 | Many terminated instances in the list | The ASG kept replacing instances that failed health checks | Fixed the root cause (user data) and used the **Activity** tab to confirm |

---

## 11. Security notes

- The database/backend instance sits in a **private subnet** with no public IP.
- Private instances only have **outbound** internet via NAT; inbound from the internet is not possible.
- Security Groups follow **least privilege**: only the ports needed are open.
- Restrict **SSH (22)** to my own IP instead of `0.0.0.0/0` in real environments.
- User data uses **IMDSv2** (token-based) to read instance metadata.

---

## 12. Possible improvements

- Add an **Application Load Balancer** in front of the ASG so users get one stable DNS name and traffic is spread across instances.
- Add **HTTPS** using AWS Certificate Manager (ACM) and the load balancer.
- Add **scaling policies** (for example target CPU at 50%) with CloudWatch alarms.
- Use **AWS Systems Manager Session Manager** instead of SSH.
- Place a NAT Gateway in **each Availability Zone** for higher availability.
- Use **Amazon RDS** for a managed production database.
- Define everything as code using **Terraform** or **CloudFormation**.

---

## 13. Cost and cleanup

> **Warning:** A **NAT Gateway** and **Elastic IP** are billed while they exist. Delete them when you finish.

Cleanup order:

1. Set the Auto Scaling Group desired/min capacity to `0`, then **delete the ASG**.
2. Delete the **Launch Template**.
3. Delete the **NAT Gateway**, then **release the Elastic IP**.
4. Detach and delete the **Internet Gateway**.
5. Delete the **subnets**, **route tables** and **Security Group**.
6. Delete the **VPC**.

---

## 14. What I learned

- How a VPC, subnets, route tables, Internet Gateway and NAT Gateway fit together, and what really makes a subnet public or private.
- How to automate server setup using **Launch Templates and user data**.
- How an **Auto Scaling Group** gives self-healing infrastructure.
- Reading **Linux logs** and using `systemctl` to debug real failures.
- Why OS details (Ubuntu vs Amazon Linux) change package managers and commands.
- A systematic way to troubleshoot: network, security group, instance, then application.

---

## 15. Author

**Sakshi Chavan**
Cloud and DevOps learner | AWS | Linux

- LinkedIn: [Sakshi Chavan](https://www.linkedin.com/in/sakshi-chavan-19659a2b3/)
- GitHub: [ByteHunterSakshi](https://github.com/ByteHunterSakshi)

If you found this useful, feel free to star the repo and connect with me.

`#AWS` `#Linux` `#AutoScaling` `#EC2` `#VPC` `#NATGateway` `#CloudComputing` `#DevOps`
