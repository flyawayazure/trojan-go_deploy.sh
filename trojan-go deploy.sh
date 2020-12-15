#!/bin/bash
#网页模版由 https://github.com/phlinhng 大神整理。其他细节也多有参考其脚本 https://github.com/phlinhng/v2ray-tcp-tls-web/blob/vless/src/v2gun.sh
export LC_ALL=C
#export LANG=en_US
#export LANGUAGE=en_US.UTF-8
apt -y update && apt -y upgrade && apt install -y curl socat jq unzip nginx
#读取域名
read -p "Please enter your domain: " domain

#获取最新版trojan-go
echo "Fetching latest version of Trojan-Go"
latest_version="$(curl -s "https://api.github.com/repos/p4gefau1t/trojan-go/releases" | jq '.[0].tag_name' --raw-output)"
curl -GLO https://github.com/p4gefau1t/trojan-go/releases/download/${latest_version}/trojan-go-linux-amd64.zip
unzip trojan-go-linux-amd64.zip
rm -f trojan-go-linux-amd64.zip

mv ./trojan-go /usr/local/bin/trojan-go &&chmod +x /usr/local/bin/trojan-go
mkdir /usr/local/share/trojan-go
mv ./geoip.dat /usr/local/share/trojan-go/geoip.dat
mv ./geosite.dat /usr/local/share/trojan-go/geosite.dat

mkdir /etc/trojan-go && chmod 755 /etc/trojan-go

#安装acme.sh
echo "Installing acme.sh"
curl  https://get.acme.sh | sh

#签发及安装证书
echo "Issuing certificate"
~/.acme.sh/acme.sh --issue -d "$domain" -w /var/www/html --keylength ec-256

echo "Installing certificate"
mkdir /etc/trojan-go/ssl&&chmod +x /etc/trojan-go/ssl

~/.acme.sh/acme.sh --install-cert --ecc --force -d "$domain" \
    --key-file       /etc/trojan-go/ssl/key.pem              \
    --fullchain-file /etc/trojan-go/ssl/fullchain-cert.pem   \
    --reloadcmd      "systemctl restart trojan-go.service"

chmod 644 /etc/trojan-go/ssl/key.pem 
chmod 644 /etc/trojan-go/ssl/fullchain-cert.pem

~/.acme.sh/acme.sh  --upgrade  --auto-upgrade

#建立伪装网站
echo "Deploying dummy website for anti-probing"
template="$(curl -s https://raw.githubusercontent.com/phlinhng/web-templates/master/list.txt | shuf -n  1)"
curl https://raw.githubusercontent.com/phlinhng/web-templates/master/${template} -o /tmp/template.zip
mkdir -p /var/www/html
unzip -q /tmp/template.zip -d /var/www/html

curl https://raw.githubusercontent.com/phlinhng/v2ray-tcp-tls-web/${branch}/custom/robots.txt -o /var/www/html/robots.txt 
cat > "/var/wwww/html/400.html" <<-EOF
<html>
<head></head>
<body>an http request has been send to https port</body>
</html>
EOF

cat > "/etc/nginx/sites-enabled/dummyweb.conf" <<-EOF
server {
    listen 127.0.0.1:888;
    server_name $domain;
    root /var/www/html;
    index index.php index.html index.htm;
    error_page 400 400.html；
}
EOF

systemctl restart nginx

#设置trojan-go.service
useradd --inactive 0 --no-create-home --uid 211 --user-group --shell /usr/bin/nologin --system trojan-go

cat > "/etc/systemd/system/trojan-go.service" <<-EOF
[Unit]
Description=Trojan-Go - An unidentifiable mechanism that helps you bypass GFW
Documentation=https://p4gefau1t.github.io/trojan-go/
After=network.target nss-lookup.target

[Service]
User=trojan-go
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/trojan-go -config /etc/trojan-go/config.yaml
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

systemctl enable trojan-go 
systemctl daemon-reload

#部署trojan-go
password="$(openssl rand -hex 12)"
read -p "Do you want to enable websocket? [y/n]" yn
if ["$yn"="Y"] || ["$yn"="y"];then
ws_path="$(openssl rand -hex 6)"
cat > "/etc/trojan-go/config.yaml" <<-EOF
run-type: server
local-addr: 0.0.0.0
local-port: 443
remote-addr: 127.0.0.1
remote-port: 888
password:
  - $password 
ssl:
  cert:/etc/trojan-go/ssl/fullchain-cert.pem  
  key: /etc/trojan-go/ssl/key.pem
  sni: $domain
  fallback_port: 888
router:
  enabled: true
  block:
    - 'geoip:private'
  geoip: /usr/local/share/trojan-go/geoip.dat
  geosite: /usr/local/share/trojan-go/geosite.dat
websocket:
  enabled: true
  path: $ws_path
  host: $domain
EOF
fi

if ["$yn"="N"] || ["$yn"="n"];then
cat > "/etc/trojan-go/config.yaml" <<-EOF
run-type: server
local-addr: 0.0.0.0
local-port: 443
remote-addr: 127.0.0.1
remote-port: 888
password:
  - $password 
ssl:
  cert:/etc/trojan-go/ssl/fullchain-cert.pem  
  key: /etc/trojan-go/ssl/key.pem
  sni: $domain
  fallback_port: 888
router:
  enabled: true
  block:
    - 'geoip:private'
  geoip: /usr/local/share/trojan-go/geoip.dat
  geosite: /usr/local/share/trojan-go/geosite.dat
EOF
fi

chmod 644 /etc/trojan-go/config.yaml
systemctl start trojan-go
echo "Trojan-Go has been deployed in your server"

#开启bbr
if sysctl net.ipv4.tcp_available_congestion_control | grep bbr &>/dev/null; then
    echo "enable bbr now"
    # curl https://raw.githubusercontent.com/unknowndev233/my_etc-/master/Arch/etc/sysctl.d/60-enable-tcp_bbr.conf -o /etc/sysctl.d/60-enable-tcp_bbr.conf
    echo "net.core.default_qdisc=cake" >> /etc/sysctl.d/60-enable-tcp_bbr.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.d/60-enable-tcp_bbr.conf
else
    echo "Not support bbr" >&2
fi

#显示分享链接
if ["$yn"="Y"] || ["$yn"="y"];then
echo "your trojan-go url is trojan-go://{$password}@{$domain}:443/?sni={$domain}&type=ws&path={$ws_path}"
fi
if ["$yn"="N"] || ["$yn"="n"];then
echo "your trojan-go url is trojan-go://{$password}@{$domain}:443/?sni={$domain}&type=original"
fi
echo "if the url is incorrect you may enter the node information manually referring to /etc/trojan-go/config.yaml "
