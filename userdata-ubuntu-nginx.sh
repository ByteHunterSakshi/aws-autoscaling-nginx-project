#!/bin/bash
apt-get update -y
apt-get install -y nginx
systemctl enable --now nginx

# Instance details (IMDSv2)
TOKEN=$(curl -s -X PUT "http://169.254.169.254/latest/api/token" \
  -H "X-aws-ec2-metadata-token-ttl-seconds: 21600")
INSTANCE_ID=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/instance-id)
AZ=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/placement/availability-zone)
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" \
  http://169.254.169.254/latest/meta-data/local-ipv4)

cat > /var/www/html/index.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>AWS Auto Scaling Demo</title>
<style>
  * { margin:0; padding:0; box-sizing:border-box; }
  body {
    min-height:100vh; display:flex; align-items:center; justify-content:center;
    font-family:'Segoe UI', Roboto, Arial, sans-serif; color:#fff;
    background:linear-gradient(135deg,#0f2027,#203a43,#2c5364);
    background-size:300% 300%; animation:bg 12s ease infinite;
  }
  @keyframes bg { 0%{background-position:0% 50%} 50%{background-position:100% 50%} 100%{background-position:0% 50%} }
  .card {
    width:90%; max-width:560px; padding:40px 32px; text-align:center;
    background:rgba(255,255,255,.08); border:1px solid rgba(255,255,255,.18);
    border-radius:20px; backdrop-filter:blur(12px);
    box-shadow:0 20px 50px rgba(0,0,0,.4);
  }
  .rocket { font-size:56px; animation:float 3s ease-in-out infinite; display:inline-block; }
  @keyframes float { 0%,100%{transform:translateY(0)} 50%{transform:translateY(-12px)} }
  h1 { margin:12px 0 6px; font-size:30px; }
  .sub { color:#9fd3e6; margin-bottom:26px; }
  .info { display:grid; gap:12px; text-align:left; }
  .row {
    display:flex; justify-content:space-between; padding:12px 16px;
    background:rgba(0,0,0,.25); border-radius:12px; font-size:15px;
  }
  .row span:first-child { color:#9fd3e6; }
  .row span:last-child { font-weight:600; }
  .badge {
    display:inline-block; margin-top:24px; padding:8px 18px; border-radius:999px;
    background:#22c55e; color:#06240f; font-weight:700; font-size:14px;
  }
  .foot { margin-top:18px; font-size:12px; color:#b6c9d3; }
</style>
</head>
<body>
  <div class="card">
    <div class="rocket">🚀</div>
    <h1>Hello from AWS Auto Scaling!</h1>
    <p class="sub">Your Launch Template user data worked successfully</p>
    <div class="info">
      <div class="row"><span>Instance ID</span><span>__INSTANCE_ID__</span></div>
      <div class="row"><span>Availability Zone</span><span>__AZ__</span></div>
      <div class="row"><span>Private IP</span><span>__PRIVATE_IP__</span></div>
      <div class="row"><span>Web Server</span><span>Nginx on Ubuntu</span></div>
    </div>
    <div class="badge">● Server is running</div>
    <p class="foot">Refresh the page behind a Load Balancer to see different instances</p>
  </div>
</body>
</html>
EOF

sed -i "s/__INSTANCE_ID__/$INSTANCE_ID/; s/__AZ__/$AZ/; s/__PRIVATE_IP__/$PRIVATE_IP/" /var/www/html/index.html
