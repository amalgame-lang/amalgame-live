# Deploying Amalgame Live to demo.amalgame.me

Target: a Linux server (root), app under `/var/mosaic/demo`, plain HTTP on
`:8080`, Caddy terminating TLS on `:8443` with Let's Encrypt.

DNS is already set: `demo.amalgame.me → 212.227.28.96`.

## 1. Get the binary onto the server

The `server` binary is a native ELF that links libgc, OpenSSL and nghttp2
dynamically. Easiest path is to build it in the dev VM and copy it up with the
runtime assets:

```bash
# in the dev VM, from the repo root
./build.sh

# copy the binary + everything it serves
scp server                 root@212.227.28.96:/var/mosaic/demo/
scp -r public              root@212.227.28.96:/var/mosaic/demo/
```

On the server, install the shared libs if missing:

```bash
apt-get update
apt-get install -y libgc1 libssl3 libnghttp2-14 zlib1g
```

(If `libgc1` isn't found, the package may be `libgc1c2` or `libgc-dev`.)

Smoke-test it by hand first:

```bash
cd /var/mosaic/demo
PORT=8080 STATE_FILE=/var/mosaic/demo/state.json ./server
# in another shell:  curl -s localhost:8080/api/state
```

## 2. Run it as a service (systemd)

```bash
cp deploy/amalgame-live.service /etc/systemd/system/
# edit the file to set RESET_KEY=... if you want a protected reset
systemctl daemon-reload
systemctl enable --now amalgame-live
systemctl status amalgame-live
journalctl -u amalgame-live -f
```

## 3. TLS on :8443 with Caddy

Install Caddy (Debian/Ubuntu):

```bash
apt-get install -y debian-keyring debian-archive-keyring apt-transport-https curl
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
apt-get update && apt-get install -y caddy
```

Drop in the site config:

```bash
cp deploy/Caddyfile /etc/caddy/Caddyfile
systemctl restart caddy
journalctl -u caddy -f          # watch the cert get issued
```

**ACME challenge ports:** the site is on `:8443`, but Caddy solves the
Let's Encrypt challenge on the standard ports — **port 80 must be open** to the
internet (HTTP-01), or port 443 (TLS-ALPN-01). Open the firewall accordingly:

```bash
ufw allow 80,443,8080,8443/tcp   # if ufw is in use
```

## 4. (Optional) self-hosted QR code

The projector page shows a QR for `https://demo.amalgame.me:8443/join`. By
default it falls back to a public QR image service. To host it yourself with
zero external calls:

```bash
apt-get install -y qrencode
qrencode -o /var/mosaic/demo/public/qr.png -s 10 -m 2 'https://demo.amalgame.me:8443/join'
```

The page prefers `/qr.png` when present.

## 5. Verify end to end

```bash
curl -s https://demo.amalgame.me:8443/api/state
```

Open `https://demo.amalgame.me:8443/` on the projector and `…/join` on a phone.

## Reset between runs

```bash
curl -s -X POST https://demo.amalgame.me:8443/api/reset -d '{"key":"<RESET_KEY>"}'
```
