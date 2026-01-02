# n8n Production Installer (Nginx + Docker)

Script này dùng để **cài đặt n8n chuẩn production trên VPS riêng** với kiến trúc:

* Docker + Docker Compose
* Nginx (system service) làm reverse proxy
* Let's Encrypt (Certbot) cấp SSL
* n8n chỉ listen nội bộ (127.0.0.1)
* An toàn khi reboot VPS

> Phù hợp cho VPS Ubuntu 20.04 / 22.04

---

## 🚀 Quick Install

Run the following command on an Ubuntu VPS:

```bash
curl -sSL https://raw.githubusercontent.com/Vanquan99/auto-install-n8n/main/install_n8n.sh \
  > install_n8n.sh && chmod +x install_n8n.sh && sudo ./install_n8n.sh
```
OR version lastest
```bash
curl -sSL https://raw.githubusercontent.com/Vanquan99/auto-install-n8n/main/install_n8n.sh | sudo bash

```

## 🚀 Quick Update Version

Update latest

Update n8n safely:

sudo ./update_n8n.sh

Update to specific version:

sudo N8N_VERSION=1.26.0 ./update_n8n.sh

Recommand
```bash
curl -sSL https://raw.githubusercontent.com/Vanquan99/auto-install-n8n/main/update_n8n.sh | sudo bash
```

OR version 
```bash
curl -sSL https://raw.githubusercontent.com/Vanquan99/auto-install-n8n/main/update_n8n.sh \
  | sudo N8N_VERSION=1.26.0 bash
```

---

## 1. Kiến trúc tổng thể

```
Internet
   ↓
Nginx (80/443 + SSL)
   ↓
Docker container n8n (127.0.0.1:5678)
```

Nguyên tắc thiết kế:

* Chỉ **1 reverse proxy duy nhất (Nginx)**
* Không dùng Caddy / Traefik
* Không expose port n8n ra public
* Docker + Nginx tự khởi động sau reboot

---

## 2. Yêu cầu trước khi cài

### VPS

* Ubuntu 20.04 hoặc 22.04
* Tối thiểu: 1 vCPU, 2GB RAM (khuyến nghị)
* Có quyền `root`

### Domain

* Có domain hoặc subdomain (ví dụ: `n8n.example.com`)
* DNS **A record trỏ về IP của VPS**

Kiểm tra nhanh:

```bash
ping n8n.example.com
```

---

## 3. Cách sử dụng nhanh (Quick Start)

### Bước 1: Clone hoặc tải script

```bash
curl -O https://raw.githubusercontent.com/<your-username>/<your-repo>/main/install_n8n_nginx.sh
```

### Bước 2: Cấp quyền thực thi

```bash
chmod +x install_n8n_nginx.sh
```

### Bước 3: Chạy script với quyền root

```bash
sudo ./install_n8n_nginx.sh
```

### Bước 4: Nhập domain khi được hỏi

Ví dụ:

```text
Enter your domain or subdomain: n8n.example.com
```

Script sẽ tự động:

* Kiểm tra domain đã trỏ đúng IP hay chưa
* Cài Docker, Docker Compose, Nginx, Certbot
* Deploy n8n bằng Docker
* Cấu hình Nginx reverse proxy
* Cấp SSL Let's Encrypt

---

## 4. Sau khi cài xong

Truy cập n8n tại:

```
https://<your-domain>
```

Kiểm tra container:

```bash
docker ps
```

Kiểm tra Nginx:

```bash
systemctl status nginx
```

Test nội bộ n8n:

```bash
curl http://127.0.0.1:5678
```

---

## 5. Cấu trúc thư mục

```
/home/n8n
 ├── docker-compose.yml
 └── docker volume: n8n_data
```

Dữ liệu n8n được lưu trong Docker volume:

```
n8n_data
```

> Khi update container hoặc reboot VPS **không mất data**.

---

## 6. Update n8n

```bash
cd /home/n8n
docker-compose pull
docker-compose up -d
```

---

## 7. Backup dữ liệu (khuyến nghị)

### Backup volume thủ công

```bash
docker run --rm \
  -v n8n_data:/data \
  -v $(pwd):/backup \
  busybox \
  tar czf /backup/n8n_backup_$(date +%F).tar.gz /data
```

---

## 8. Lỗi thường gặp

### Domain chưa trỏ đúng IP

Script sẽ dừng với thông báo:

```text
Domain is not pointing to this server
```

→ Cập nhật DNS rồi chạy lại script.

---

### 502 Bad Gateway

Nguyên nhân:

* n8n container chưa chạy
* Port 5678 bị đổi

Kiểm tra:

```bash
docker ps
curl http://127.0.0.1:5678
```

---

### HTTPS loop / webhook lỗi

Đảm bảo trong `docker-compose.yml`:

```env
N8N_PROTOCOL=https
WEBHOOK_URL=https://<your-domain>/
```

---

## 9. Bảo mật khuyến nghị

* Bật **Basic Auth** cho n8n
* Giới hạn IP truy cập bằng Nginx hoặc VPN
* Không expose port 5678 ra public
* Backup dữ liệu định kỳ

---

## 10. Roadmap (tùy chọn mở rộng)

* [ ] PostgreSQL thay cho SQLite
* [ ] Multi-instance n8n
* [ ] Cloudflare Full SSL
* [ ] Auto backup bằng cron
* [ ] IP allowlist

---

## 11. License

MIT License

---

## 12. Credits

Script được xây dựng lại và chuẩn hóa cho môi trường production, dựa trên kinh nghiệm triển khai n8n thực tế trên VPS.
