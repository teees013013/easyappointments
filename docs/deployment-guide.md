# EasyAppointments Multi-Instance Deployment Guide

Complete step-by-step guide to setting up cloud infrastructure and deploying EasyAppointments as multi-instance booking infrastructure for your SaaS products.

**Architecture:** One production Docker image, deployed as separate containers per product, each with its own database on a shared MySQL server, managed by Coolify on a VPS.

**Time estimate:** 2-3 hours for first-time setup. 10 minutes per additional product instance after that.

---

## Table of Contents

1. [Prerequisites and Accounts](#1-prerequisites-and-accounts)
2. [VPS Server Setup](#2-vps-server-setup)
3. [Domain and DNS Setup](#3-domain-and-dns-setup)
4. [Install Coolify](#4-install-coolify)
5. [Container Registry Setup](#5-container-registry-setup)
6. [MySQL Database Setup](#6-mysql-database-setup)
7. [SMTP Email Setup](#7-smtp-email-setup)
8. [Google Calendar Sync Setup (Optional)](#8-google-calendar-sync-setup-optional)
9. [Build and Push the Docker Image](#9-build-and-push-the-docker-image)
10. [Deploy Your First Instance](#10-deploy-your-first-instance)
11. [Configure EasyAppointments](#11-configure-easyappointments)
12. [Deploy Additional Instances](#12-deploy-additional-instances)
13. [Integrate With Your Product](#13-integrate-with-your-product)
14. [Upgrades and Maintenance](#14-upgrades-and-maintenance)
15. [Monitoring and Backups](#15-monitoring-and-backups)
16. [Troubleshooting](#16-troubleshooting)

---

## 1. Prerequisites and Accounts

You will need accounts with the following services. Create these before starting.

### Required

| Service | Purpose | Sign Up |
|---------|---------|---------|
| **VPS Provider** (Hetzner, DigitalOcean, or Vultr) | Server to run Coolify + all instances | See [Section 2](#2-vps-server-setup) |
| **Domain registrar** (Cloudflare, Namecheap, etc.) | DNS for `*.bookings.yourdomain.com` | See [Section 3](#3-domain-and-dns-setup) |
| **GitHub** | Source code hosting, container registry | https://github.com/signup |
| **SMTP provider** (Resend, Postmark, or Amazon SES) | Transactional email from instances | See [Section 7](#7-smtp-email-setup) |

### Optional

| Service | Purpose | Sign Up |
|---------|---------|---------|
| **Google Cloud** | Google Calendar sync (OAuth credentials) | See [Section 8](#8-google-calendar-sync-setup-optional) |

### On Your Local Machine

- **Docker Desktop** installed and running
- **Git** installed
- **SSH key** generated (`ssh-keygen -t ed25519` if you don't have one)
- This repository cloned locally

---

## 2. VPS Server Setup

You need a Linux server to run Coolify and all your EasyAppointments instances. Each instance uses roughly 60-80 MB of RAM, so a small VPS handles 4-10 instances easily.

### Option A: Hetzner (Recommended - Best Price/Performance)

Hetzner offers the best value for European and US-based deployments.

1. **Create account:** https://accounts.hetzner.com/signUp
2. **Add payment method:** Credit card or PayPal
3. **Create a server:**
   - Go to **Cloud Console** > **Servers** > **Add Server**
   - **Location:** Choose closest to your users (Ashburn, Hillsboro, or Falkenstein/Helsinki for EU)
   - **Image:** Ubuntu 24.04
   - **Type:** CX22 (2 vCPU, 4 GB RAM, 40 GB disk) — ~$4.50/month, handles 10+ instances
   - **Networking:** Enable IPv4 and IPv6
   - **SSH Keys:** Click **Add SSH Key**, paste your public key (`cat ~/.ssh/id_ed25519.pub`)
   - **Name:** `coolify-prod` (or whatever you prefer)
   - Click **Create & Buy Now**
4. **Note the IP address** shown after creation (e.g., `65.109.xxx.xxx`)

### Option B: DigitalOcean

1. **Create account:** https://cloud.digitalocean.com/registrations/new
2. **Create a Droplet:**
   - Click **Create** > **Droplets**
   - **Region:** Closest to your users
   - **Image:** Ubuntu 24.04 LTS
   - **Size:** Basic > Regular > $6/month (1 vCPU, 1 GB RAM) or $12/month (2 vCPU, 2 GB RAM)
   - **Authentication:** SSH Key (add your public key)
   - **Hostname:** `coolify-prod`
   - Click **Create Droplet**
3. **Note the IP address**

### Option C: Vultr

1. **Create account:** https://www.vultr.com/register/
2. **Deploy new instance:**
   - Click **Deploy** > **Cloud Compute**
   - **Location:** Closest to your users
   - **Image:** Ubuntu 24.04 LTS
   - **Plan:** Regular Performance > $6/month (1 vCPU, 1 GB RAM)
   - **SSH Key:** Add your public key
   - **Hostname:** `coolify-prod`
   - Click **Deploy Now**
3. **Note the IP address**

### After Server Creation (All Providers)

Verify you can SSH into your server:

```bash
ssh root@YOUR_SERVER_IP
```

You should see a welcome message. If this works, proceed to the next step. If not, check that your SSH key was added correctly.

---

## 3. Domain and DNS Setup

You need a domain with wildcard subdomain support so each product gets its own booking URL (e.g., `product-a.bookings.yourdomain.com`).

### If You Already Own a Domain

You can use a subdomain of an existing domain. No need to buy a new one.

### If You Need a New Domain

Purchase from any registrar. Cloudflare Registrar is recommended because it offers free DNS management and proxied SSL.

### DNS Configuration

You need **two DNS records** — one for Coolify itself and one wildcard for all booking instances.

Log into your DNS provider (Cloudflare, Namecheap, Route53, etc.) and add:

| Type | Name | Value | Proxy | TTL |
|------|------|-------|-------|-----|
| `A` | `coolify` | `YOUR_SERVER_IP` | Off (DNS only) | Auto |
| `A` | `*.bookings` | `YOUR_SERVER_IP` | Off (DNS only) | Auto |

This gives you:
- `coolify.yourdomain.com` — Coolify admin dashboard
- `*.bookings.yourdomain.com` — All EasyAppointments instances

**Important:** If using Cloudflare, set the proxy toggle to **DNS only** (grey cloud) for both records. Coolify's Traefik handles SSL itself via Let's Encrypt — Cloudflare's proxy would interfere with certificate issuance.

### Verify DNS Propagation

Wait a few minutes, then verify:

```bash
dig +short coolify.yourdomain.com
# Should return: YOUR_SERVER_IP

dig +short anything.bookings.yourdomain.com
# Should return: YOUR_SERVER_IP
```

If using Cloudflare with proxy on, `dig` will return Cloudflare IPs instead. That's why we recommend proxy off for these records.

---

## 4. Install Coolify

Coolify is a self-hosted PaaS (like Heroku/Vercel but on your own server). It manages Docker containers, SSL certificates, and deployments.

### Step 1: SSH Into Your Server

```bash
ssh root@YOUR_SERVER_IP
```

### Step 2: Run the Coolify Installer

```bash
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash
```

This installs Docker, Coolify, and all dependencies. It takes 2-5 minutes.

### Step 3: Access the Coolify Dashboard

Open your browser and go to:

```
http://YOUR_SERVER_IP:8000
```

(Use the raw IP — the domain won't work until Coolify is configured.)

### Step 4: Create Your Admin Account

- **Email:** Your email address
- **Password:** Choose a strong password
- Click **Register**

### Step 5: Initial Configuration

1. **Server:** Coolify auto-detects the localhost server. Click **Validate** to confirm Docker is running.
2. **Settings** > **General:**
   - Set **Instance's Domain** to `https://coolify.yourdomain.com`
   - Enable **Auto Update** if you want Coolify to stay current
3. **Settings** > **SSL:**
   - The Coolify dashboard will now be accessible at `https://coolify.yourdomain.com` with auto-provisioned SSL

### Step 6: Verify Dashboard Access

Navigate to `https://coolify.yourdomain.com` and log in. If SSL works and you can see the dashboard, Coolify is ready.

---

## 5. Container Registry Setup

You need somewhere to store your built Docker image so Coolify can pull it. GitHub Container Registry (GHCR) is free and integrates with GitHub.

### Option A: GitHub Container Registry (Recommended)

#### Step 1: Create a Personal Access Token

1. Go to https://github.com/settings/tokens?type=beta
2. Click **Generate new token**
3. **Token name:** `coolify-ghcr`
4. **Expiration:** Choose your preference (90 days, or no expiration for production)
5. **Repository access:** Select **Only select repositories** > choose your easyappointments fork
6. **Permissions:**
   - **Packages:** Read and write
7. Click **Generate token**
8. **Copy the token** — you will not see it again

#### Step 2: Log In to GHCR Locally

```bash
echo "YOUR_TOKEN" | docker login ghcr.io -u YOUR_GITHUB_USERNAME --password-stdin
```

You should see `Login Succeeded`.

#### Step 3: Add GHCR to Coolify

1. In Coolify, go to **Security** > **Private Keys** and add your server's SSH key if not already there
2. Go to **Sources** and note that Coolify can pull from Docker registries
3. When deploying services later, you'll provide the full image URL (`ghcr.io/yourusername/easyappointments:latest`)

### Option B: Docker Hub

If you prefer Docker Hub:

1. Create account at https://hub.docker.com/signup
2. Create a repository named `easyappointments`
3. Log in locally: `docker login -u YOUR_DOCKERHUB_USERNAME`
4. Your image URL will be `yourusername/easyappointments:latest`

### Option C: Build Directly on Server

If you don't want a registry, you can clone the repo on your server and build there:

```bash
# On your server
git clone https://github.com/YOUR_USERNAME/easyappointments.git
cd easyappointments
docker build -f Dockerfile.production -t ea-production:latest .
```

This is simpler but means you need to SSH into the server and rebuild for each update.

---

## 6. MySQL Database Setup

All EasyAppointments instances share a single MySQL server, each with its own database and dedicated user.

### Step 1: Create MySQL Service in Coolify

1. In Coolify, go to **Projects** > **Default** (or create a new project called "Booking Infrastructure")
2. Click **+ New** > **Database** > **MySQL**
3. Configure:
   - **Name:** `booking-mysql`
   - **Version:** MySQL 8.0 (or 8.4)
   - **Root Password:** Generate a strong password and **save it securely** (you'll need this for the provisioning script)
   - **Default Database:** `mysql` (leave default)
   - **Network:** Keep on Coolify's internal network
   - **Persistent Storage:** Enabled (this is the default — your data survives container restarts)
4. Click **Deploy**

### Step 2: Note the Internal Hostname

After deployment, go to the MySQL service details. Note the **internal hostname** — this is what your EA containers use to connect. In Coolify, this is typically the service UUID or a name like `booking-mysql`.

You can find it under the service's **General** tab. It will look something like:

```
booking-mysql
```

Or you can use the Coolify internal DNS format. The exact hostname depends on your Coolify version, but it's visible in the service configuration.

### Step 3: Test the Connection

From the Coolify terminal (or by exec-ing into the MySQL container):

```bash
docker exec -it <mysql-container-id> mysql -u root -p
```

Enter the root password. If you get a MySQL prompt, the database server is running.

### Step 4: Provision Your First Instance Database

You can either run the provisioning script from your local machine (if MySQL is accessible) or from the server.

**From the server (recommended):**

```bash
# Clone your repo on the server (if not already done)
cd /path/to/easyappointments

# Run the provisioning script
./scripts/provision-instance.sh product-a booking-mysql YOUR_MYSQL_ROOT_PASSWORD
```

**Output will look like:**

```
=== EasyAppointments Instance Provisioner ===

Product:  product-a
Database: ea_product_a
DB User:  ea_product_a

=== Database created successfully ===

=== Coolify Environment Variables ===
Copy these into your Coolify service configuration:

EA_BASE_URL=https://product-a.bookings.yourdomain.com
EA_DB_HOST=booking-mysql
EA_DB_NAME=ea_product_a
EA_DB_USERNAME=ea_product_a
EA_DB_PASSWORD=aBcDeFgHiJkLmNoPqRsT
EA_ENCRYPTION_KEY=xYz123...==
EA_CORS_ORIGINS=https://app.product-a.com
EA_FRAME_ANCESTORS=https://app.product-a.com
EA_PROXY_IPS=172.16.0.0/12
```

**Save this output** — you'll paste it into Coolify when deploying the instance.

---

## 7. SMTP Email Setup

EasyAppointments sends emails for appointment confirmations, reminders, and cancellations. You need an SMTP provider.

### Option A: Resend (Recommended for Simplicity)

Resend offers a generous free tier (100 emails/day, 3,000/month) and simple SMTP credentials.

1. **Create account:** https://resend.com/signup
2. **Verify your domain:**
   - Go to **Domains** > **Add Domain**
   - Enter your domain (e.g., `yourdomain.com` or `bookings.yourdomain.com`)
   - Add the DNS records Resend shows you (SPF, DKIM, DMARC):

     | Type | Name | Value |
     |------|------|-------|
     | `TXT` | `@` or subdomain | SPF record provided by Resend |
     | `CNAME` | As shown | DKIM record provided by Resend |
     | `TXT` | `_dmarc` | DMARC record provided by Resend |

   - Click **Verify** after adding DNS records (may take a few minutes)
3. **Generate API key:**
   - Go to **API Keys** > **Create API Key**
   - **Name:** `easyappointments`
   - **Permission:** Sending access
   - Copy the key
4. **SMTP credentials for EasyAppointments:**

   ```
   EA_SMTP_HOST=smtp.resend.com
   EA_SMTP_PORT=587
   EA_SMTP_USER=resend
   EA_SMTP_PASS=re_YOUR_API_KEY
   EA_SMTP_CRYPTO=tls
   EA_MAIL_FROM_ADDRESS=bookings@yourdomain.com
   EA_MAIL_FROM_NAME=Your Company Bookings
   ```

### Option B: Postmark (Best Deliverability)

Postmark is known for excellent deliverability. Free trial with 100 emails/month, then $15/month for 10,000.

1. **Create account:** https://account.postmarkapp.com/sign_up
2. **Create a Server:**
   - Click **Servers** > **Create Server**
   - Name it `EasyAppointments`
3. **Verify sender domain:**
   - Go to **Sender Signatures** > **Add Domain**
   - Add DNS records as prompted
4. **SMTP credentials** (found under **Server** > **Default Message Stream** > **Settings**):

   ```
   EA_SMTP_HOST=smtp.postmarkapp.com
   EA_SMTP_PORT=587
   EA_SMTP_USER=YOUR_SERVER_API_TOKEN
   EA_SMTP_PASS=YOUR_SERVER_API_TOKEN
   EA_SMTP_CRYPTO=tls
   EA_MAIL_FROM_ADDRESS=bookings@yourdomain.com
   EA_MAIL_FROM_NAME=Your Company Bookings
   ```

### Option C: Amazon SES (Cheapest at Scale)

Amazon SES costs $0.10 per 1,000 emails. Best if you already use AWS.

1. **Create AWS account:** https://aws.amazon.com/ (if you don't have one)
2. **Navigate to SES:** AWS Console > Search "SES" > Amazon Simple Email Service
3. **Verify domain:**
   - Go to **Identities** > **Create Identity** > **Domain**
   - Enter your domain and follow DNS verification steps
4. **Request production access:**
   - By default, SES is in sandbox mode (can only send to verified emails)
   - Go to **Account Dashboard** > **Request Production Access**
   - Fill out the form explaining your use case
   - Approval typically takes 24-48 hours
5. **Create SMTP credentials:**
   - Go to **SMTP Settings** > **Create SMTP Credentials**
   - Note the **SMTP endpoint** for your region (e.g., `email-smtp.us-east-1.amazonaws.com`)
   - Copy the generated username and password

   ```
   EA_SMTP_HOST=email-smtp.us-east-1.amazonaws.com
   EA_SMTP_PORT=587
   EA_SMTP_USER=AKIAXXXXXXXXXXXXXXXX
   EA_SMTP_PASS=YOUR_SMTP_PASSWORD
   EA_SMTP_CRYPTO=tls
   EA_MAIL_FROM_ADDRESS=bookings@yourdomain.com
   EA_MAIL_FROM_NAME=Your Company Bookings
   ```

### Shared vs. Per-Instance SMTP

You can use the **same SMTP credentials** across all instances. The only values that might differ per instance are:

- `EA_MAIL_FROM_ADDRESS` — You might want `product-a-bookings@yourdomain.com` vs `product-b-bookings@yourdomain.com`
- `EA_MAIL_FROM_NAME` — You might want each product's name

The SMTP host, user, and password can be the same for all instances.

---

## 8. Google Calendar Sync Setup (Optional)

If your users need Google Calendar integration, you need a Google Cloud project with OAuth credentials.

### Step 1: Create a Google Cloud Project

1. Go to https://console.cloud.google.com/
2. **Create account** if you don't have one (requires a Google account)
3. Click the project dropdown (top-left) > **New Project**
   - **Name:** `EasyAppointments Bookings`
   - **Organization:** Leave as is
   - Click **Create**

### Step 2: Enable the Google Calendar API

1. In the left sidebar, go to **APIs & Services** > **Library**
2. Search for "Google Calendar API"
3. Click on it > **Enable**

### Step 3: Configure the OAuth Consent Screen

1. Go to **APIs & Services** > **OAuth consent screen**
2. Choose **External** (unless you have Google Workspace and want internal only)
3. Fill in:
   - **App name:** `EasyAppointments Bookings` (or your product name)
   - **User support email:** Your email
   - **Developer contact email:** Your email
4. Click **Save and Continue**
5. **Scopes:** Click **Add or Remove Scopes**
   - Search for and add: `https://www.googleapis.com/auth/calendar`
   - Click **Update** > **Save and Continue**
6. **Test Users:** Add your own email for testing
7. Click **Save and Continue** > **Back to Dashboard**

### Step 4: Create OAuth Credentials (One Per Instance)

Each EasyAppointments instance needs its own OAuth client ID because the redirect URI is unique per subdomain.

1. Go to **APIs & Services** > **Credentials**
2. Click **+ Create Credentials** > **OAuth 2.0 Client ID**
3. **Application type:** Web application
4. **Name:** `EA - Product A` (name it after your product)
5. **Authorized redirect URIs:** Click **Add URI** and enter:
   ```
   https://product-a.bookings.yourdomain.com/google/callback
   ```
6. Click **Create**
7. **Copy the Client ID and Client Secret**

For the env vars:

```
EA_GOOGLE_SYNC=true
EA_GOOGLE_CLIENT_ID=123456789-xxxx.apps.googleusercontent.com
EA_GOOGLE_CLIENT_SECRET=GOCSPX-xxxxxxxxxxxxx
```

### Step 5: Repeat for Additional Instances

For each new EasyAppointments instance:

1. Go to **Credentials** > **+ Create Credentials** > **OAuth 2.0 Client ID**
2. **Name:** `EA - Product B`
3. **Redirect URI:** `https://product-b.bookings.yourdomain.com/google/callback`
4. Copy credentials into that instance's env vars

### Publishing the App

While in testing mode, only the test users you added can use Google Calendar sync. To allow all users:

1. Go to **OAuth consent screen** > **Publishing status**
2. Click **Publish App**
3. Google may require a verification review (takes days to weeks). Until approved, users see a "This app isn't verified" warning but can still proceed by clicking "Advanced" > "Go to [app]"

---

## 9. Build and Push the Docker Image

### Step 1: Build the Production Image

From your local machine, in the repository root:

```bash
docker build -f Dockerfile.production -t ea-production:latest .
```

This takes 3-5 minutes on first build (subsequent builds are faster due to layer caching).

### Step 2: Tag and Push to Registry

**If using GitHub Container Registry (GHCR):**

```bash
# Tag the image
docker tag ea-production:latest ghcr.io/YOUR_GITHUB_USERNAME/easyappointments:latest

# Push to registry
docker push ghcr.io/YOUR_GITHUB_USERNAME/easyappointments:latest
```

**If using Docker Hub:**

```bash
docker tag ea-production:latest YOUR_DOCKERHUB_USERNAME/easyappointments:latest
docker push YOUR_DOCKERHUB_USERNAME/easyappointments:latest
```

**If building directly on the server:**

```bash
# SSH into server
ssh root@YOUR_SERVER_IP

# Clone repo and build
git clone https://github.com/YOUR_USERNAME/easyappointments.git /opt/easyappointments
cd /opt/easyappointments
docker build -f Dockerfile.production -t ea-production:latest .
```

---

## 10. Deploy Your First Instance

### Step 1: Add Registry Credentials to Coolify (GHCR/Docker Hub only)

1. In Coolify, go to **Security** > **Private Keys** (for SSH) or look for Docker Registry settings
2. For GHCR: You may need to configure the registry under your service's **General** settings when creating it

### Step 2: Create a New Service

1. In Coolify, go to **Projects** > **Your Project** > **+ New** > **Docker Image**
2. **Image:** Enter the full image URL:
   - GHCR: `ghcr.io/YOUR_GITHUB_USERNAME/easyappointments:latest`
   - Docker Hub: `YOUR_DOCKERHUB_USERNAME/easyappointments:latest`
   - Local: `ea-production:latest`
3. **Name:** `ea-product-a`

### Step 3: Configure the Domain

1. Under the service's **General** settings:
   - **Domain:** `https://product-a.bookings.yourdomain.com`
2. Coolify's Traefik will automatically provision an SSL certificate via Let's Encrypt

### Step 4: Set Environment Variables

1. Go to the service's **Environment Variables** tab
2. Add all the variables from the provisioning script output (from [Section 6, Step 4](#step-4-provision-your-first-instance-database)):

   ```
   EA_BASE_URL=https://product-a.bookings.yourdomain.com
   EA_DB_HOST=booking-mysql
   EA_DB_NAME=ea_product_a
   EA_DB_USERNAME=ea_product_a
   EA_DB_PASSWORD=aBcDeFgHiJkLmNoPqRsT
   EA_ENCRYPTION_KEY=xYz123...==
   EA_CORS_ORIGINS=https://app.product-a.com
   EA_FRAME_ANCESTORS=https://app.product-a.com
   EA_PROXY_IPS=172.16.0.0/12
   EA_SMTP_HOST=smtp.resend.com
   EA_SMTP_PORT=587
   EA_SMTP_USER=resend
   EA_SMTP_PASS=re_YOUR_API_KEY
   EA_SMTP_CRYPTO=tls
   EA_MAIL_FROM_ADDRESS=bookings@yourdomain.com
   EA_MAIL_FROM_NAME=Product A Bookings
   ```

   If using Google Calendar sync, also add:

   ```
   EA_GOOGLE_SYNC=true
   EA_GOOGLE_CLIENT_ID=your-client-id
   EA_GOOGLE_CLIENT_SECRET=your-client-secret
   ```

### Step 5: Configure Persistent Storage

1. Go to the service's **Storages** tab (or **Volumes**)
2. Add persistent volumes for data that must survive container restarts:

   | Container Path | Purpose |
   |----------------|---------|
   | `/var/www/html/storage/uploads` | Uploaded files (logos, etc.) |
   | `/var/www/html/storage/backups` | Database backups |

### Step 6: Configure Networking

1. Ensure the service is on the **same Docker network** as your MySQL service
2. In Coolify, this is typically handled automatically if both services are in the same project
3. If not, check the **Network** settings and ensure both services share a network

### Step 7: Deploy

1. Click **Deploy**
2. Watch the logs to confirm:
   - `>>> Setting storage directory permissions` — OK
   - `>>> Running database migrations` — Should complete (first run creates all tables)
   - `>>> Starting supervisord` — Nginx and PHP-FPM start
3. Wait for the SSL certificate to be issued (Traefik shows this in its logs)

### Step 8: Verify

Open `https://product-a.bookings.yourdomain.com` in your browser. You should see the EasyAppointments installation wizard.

---

## 11. Configure EasyAppointments

### Step 1: Complete the Installation Wizard

1. Visit `https://product-a.bookings.yourdomain.com`
2. The installation wizard will appear on first visit
3. Fill in:
   - **Admin First Name / Last Name:** Your name
   - **Admin Email:** Your email (used for login)
   - **Admin Password:** Choose a strong password
   - **Company Name:** Your product's company name (shown to customers)
4. Click **Install**

### Step 2: Configure Business Settings

1. Log in to the admin panel (use the credentials you just created)
2. Go to **Settings** > **General:**
   - **Company Name:** Displayed on the booking page
   - **Company Email:** Contact email
   - **Company Link:** URL to your main product
   - **Date Format / Time Format:** Choose your preference
3. Go to **Settings** > **Business Logic:**
   - **Working Hours:** Set your default availability
   - **Book in Advance (days):** How far ahead customers can book
   - **Appointment Duration:** Default appointment length

### Step 3: Create Services

1. Go to **Services** > **Add**
2. Create each bookable service:
   - **Name:** e.g., "30-Minute Consultation"
   - **Duration:** 30 minutes
   - **Price:** Optional
   - **Currency:** Optional
   - **Description:** What the customer is booking

### Step 4: Create Service Providers

1. Go to **Providers** > **Add**
2. Create each person who offers appointments:
   - **Name / Email / Phone**
   - **Services:** Assign which services this provider offers
   - **Working Plan:** Set their availability

### Step 5: Generate API Token

1. Go to **Settings** > **General**
2. Find the **API Token** field
3. Click **Generate** (or **Save** if it's auto-generated)
4. **Copy and save this token** — your product backend uses it for API calls

### Step 6: Test the Booking Page

Visit `https://product-a.bookings.yourdomain.com/booking` to see the customer-facing booking widget. Verify that services, providers, and available time slots appear correctly.

---

## 12. Deploy Additional Instances

For each new product, repeat these steps:

### 1. Provision the Database

```bash
./scripts/provision-instance.sh product-b booking-mysql YOUR_MYSQL_ROOT_PASSWORD
```

Save the output.

### 2. (If using Google Calendar) Create OAuth Credentials

Create a new OAuth 2.0 Client ID with redirect URI:
```
https://product-b.bookings.yourdomain.com/google/callback
```

### 3. Create New Service in Coolify

- Same Docker image as the first instance
- Domain: `https://product-b.bookings.yourdomain.com`
- Paste the env vars from the provisioning script
- Add SMTP and Google Calendar env vars
- Add persistent storage volumes
- Deploy

### 4. Configure EasyAppointments

Visit `https://product-b.bookings.yourdomain.com`, complete the installation wizard, configure services/providers, generate API token.

---

## 13. Integrate With Your Product

### REST API

Each instance has a full REST API at `/api/v1/`. Authenticate with the Bearer token from [Step 5 above](#step-5-generate-api-token).

```bash
# List all appointments
curl -H "Authorization: Bearer YOUR_API_TOKEN" \
  https://product-a.bookings.yourdomain.com/api/v1/appointments

# Create an appointment
curl -X POST -H "Authorization: Bearer YOUR_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"start": "2026-04-01 10:00", "end": "2026-04-01 10:30", "serviceId": 1, "providerId": 1}' \
  https://product-a.bookings.yourdomain.com/api/v1/appointments
```

API documentation: https://easyappointments.org/docs/api

### Embedding the Booking Page

Add this iframe to your product's frontend:

```html
<iframe
  src="https://product-a.bookings.yourdomain.com/booking"
  width="100%"
  height="600"
  frameborder="0"
  style="border: none;"
></iframe>
```

The `EA_FRAME_ANCESTORS` env var must include your product's domain for this to work. If your product is at `https://app.product-a.com`, set:

```
EA_FRAME_ANCESTORS=https://app.product-a.com
```

### Webhooks

EasyAppointments supports webhooks for real-time notifications. Configure them in the admin panel under **Settings** or via the API.

### CORS Configuration

If your product's frontend makes direct API calls to EasyAppointments (not just iframe embedding), set `EA_CORS_ORIGINS` to include your product's domain:

```
EA_CORS_ORIGINS=https://app.product-a.com,https://admin.product-a.com
```

Multiple origins can be comma-separated.

---

## 14. Upgrades and Maintenance

### Updating EasyAppointments

When you make changes to the fork or pull upstream updates:

```bash
# 1. Pull changes locally
git pull

# 2. Rebuild the Docker image
docker build -f Dockerfile.production -t ea-production:latest .

# 3. Tag and push to your registry
docker tag ea-production:latest ghcr.io/YOUR_GITHUB_USERNAME/easyappointments:latest
docker push ghcr.io/YOUR_GITHUB_USERNAME/easyappointments:latest

# 4. Redeploy each service in Coolify
#    Go to each EA service > click "Redeploy" (or "Pull & Redeploy")
#    The entrypoint script runs migrations automatically on startup
```

### Pulling Upstream Changes

```bash
# Add the upstream remote (one-time)
git remote add upstream https://github.com/alextselegidis/easyappointments.git

# Fetch and merge upstream changes
git fetch upstream
git merge upstream/main

# Resolve any conflicts, then rebuild and redeploy
```

### Updating Coolify

Coolify has a built-in auto-update feature, or you can manually update:

```bash
# SSH into your server
ssh root@YOUR_SERVER_IP

# Update Coolify
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash
```

---

## 15. Monitoring and Backups

### Container Logs

In Coolify, click on any EA service and view **Logs** to see nginx access logs, PHP errors, and migration output.

### MySQL Backups

#### Option A: Coolify Built-in Backups

1. Go to your MySQL service in Coolify
2. Click **Backups**
3. Configure a schedule (e.g., daily at 2 AM)
4. Set a backup retention period

#### Option B: Manual Backup Script

Create a cron job on your server:

```bash
# /opt/scripts/backup-mysql.sh
#!/bin/bash
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR=/opt/backups/mysql

mkdir -p $BACKUP_DIR

# Backup all EA databases
for DB in $(docker exec booking-mysql mysql -u root -pYOUR_ROOT_PASSWORD -e "SHOW DATABASES LIKE 'ea_%'" -s --skip-column-names); do
    docker exec booking-mysql mysqldump -u root -pYOUR_ROOT_PASSWORD $DB | gzip > $BACKUP_DIR/${DB}_${TIMESTAMP}.sql.gz
done

# Delete backups older than 30 days
find $BACKUP_DIR -name "*.sql.gz" -mtime +30 -delete
```

Add to crontab:

```bash
crontab -e
# Add:
0 2 * * * /opt/scripts/backup-mysql.sh
```

### Health Monitoring

Each EA container has a built-in health check that hits `/booking` every 30 seconds. Coolify shows the container health status in the dashboard.

For external monitoring, use a service like:

- **UptimeRobot** (free, 50 monitors): https://uptimerobot.com
- **Better Uptime** (free tier): https://betterstack.com/better-uptime

Add a monitor for each instance's booking URL:
```
https://product-a.bookings.yourdomain.com/booking
```

### Disk Space

Monitor disk usage on your server. The main consumers are:

- MySQL data (grows with appointments)
- Docker images and layers
- Log files

```bash
# Check disk usage
df -h

# Clean up old Docker images
docker image prune -a --filter "until=720h"  # Remove images older than 30 days
```

---

## 16. Troubleshooting

### Container won't start

**Check logs in Coolify.** Common issues:

| Error | Cause | Fix |
|-------|-------|-----|
| `Connection refused` on MySQL | MySQL not on same Docker network | Ensure both services share a network in Coolify |
| `Access denied for user` | Wrong DB credentials | Verify env vars match provisioning script output |
| `exec /entrypoint.sh: no such file` | Image built with bash shebang on Alpine | Rebuild image (this was fixed in our Dockerfile) |
| `Migration skipped` | Normal on first deploy before installation wizard | Complete the installation wizard at `/installation` |

### SSL certificate not issuing

1. Verify DNS records point to your server IP (not a CDN)
2. Check that port 80 and 443 are open on your server's firewall
3. Look at Traefik logs in Coolify for Let's Encrypt errors
4. Ensure Cloudflare proxy is **off** (grey cloud) if using Cloudflare DNS

### CORS errors in browser console

1. Check that `EA_CORS_ORIGINS` includes the exact origin (with protocol):
   - Correct: `https://app.product-a.com`
   - Wrong: `app.product-a.com` (missing protocol)
   - Wrong: `https://app.product-a.com/` (trailing slash)
2. Multiple origins are comma-separated: `https://app.product-a.com,https://admin.product-a.com`
3. Redeploy the container after changing env vars

### iframe not loading (blocked by browser)

1. Check `EA_FRAME_ANCESTORS` is set to your product's domain
2. The domain must match exactly (including protocol)
3. Check browser console for CSP violation messages

### Emails not sending

1. Verify SMTP credentials by testing with a tool like `swaks`:
   ```bash
   swaks --to test@example.com --from bookings@yourdomain.com \
     --server smtp.resend.com --port 587 \
     --auth-user resend --auth-password re_YOUR_API_KEY \
     --tls
   ```
2. Check that your sending domain is verified with your SMTP provider
3. Check the EA container logs for SMTP error messages

### Google Calendar sync not working

1. Verify the redirect URI matches exactly: `https://your-subdomain.bookings.yourdomain.com/google/callback`
2. Check that the Google Calendar API is enabled in your Google Cloud project
3. If users see "This app isn't verified," they can click Advanced > Go to app (or publish the app for production use)

---

## Quick Reference: Environment Variables

| Variable | Required | Example |
|----------|----------|---------|
| `EA_BASE_URL` | Yes | `https://product-a.bookings.yourdomain.com` |
| `EA_DB_HOST` | Yes | `booking-mysql` |
| `EA_DB_NAME` | Yes | `ea_product_a` |
| `EA_DB_USERNAME` | Yes | `ea_product_a` |
| `EA_DB_PASSWORD` | Yes | (from provisioning script) |
| `EA_ENCRYPTION_KEY` | Yes | (from provisioning script) |
| `EA_CORS_ORIGINS` | Production | `https://app.product-a.com` |
| `EA_FRAME_ANCESTORS` | If embedding | `https://app.product-a.com` |
| `EA_PROXY_IPS` | Yes | `172.16.0.0/12` |
| `EA_SMTP_HOST` | For email | `smtp.resend.com` |
| `EA_SMTP_PORT` | For email | `587` |
| `EA_SMTP_USER` | For email | `resend` |
| `EA_SMTP_PASS` | For email | `re_xxxxx` |
| `EA_SMTP_CRYPTO` | For email | `tls` |
| `EA_MAIL_FROM_ADDRESS` | For email | `bookings@yourdomain.com` |
| `EA_MAIL_FROM_NAME` | For email | `Product A Bookings` |
| `EA_GOOGLE_SYNC` | For calendar | `true` |
| `EA_GOOGLE_CLIENT_ID` | For calendar | `123...apps.googleusercontent.com` |
| `EA_GOOGLE_CLIENT_SECRET` | For calendar | `GOCSPX-xxxxx` |
| `EA_LANGUAGE` | No | `english` |
| `EA_DEBUG_MODE` | No | `false` |

---

## Quick Reference: Checklist Per Instance

- [ ] Run provisioning script to create database
- [ ] Create OAuth credentials (if using Google Calendar)
- [ ] Create service in Coolify with the Docker image
- [ ] Set domain to `https://<product>.bookings.yourdomain.com`
- [ ] Paste all environment variables
- [ ] Add persistent storage volumes for uploads and backups
- [ ] Deploy
- [ ] Complete installation wizard at `/installation`
- [ ] Configure services and providers
- [ ] Generate API token
- [ ] Test booking page at `/booking`
- [ ] Register webhooks (if needed)
- [ ] Test API integration from your product backend
- [ ] Test iframe embedding (if needed)
