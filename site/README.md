# SWE 645 - Assignment 1

Author: Lizon Raj

A small static website with two pages — a personal homepage and a prospective student survey form. Deployed to AWS two ways: as an S3 static website and on an Apache web server running on an EC2 instance.

## Live URLs
- S3 site: `https://s3-lizon-bucket-1.s3.us-east-1.amazonaws.com/index.html`
- EC2 site: `http://ec2-54-82-18-73.compute-1.amazonaws.com/index.html`

The survey page is linked from the homepage on both (`/survey.html`).

## Files
- `index.html` — homepage with a short intro and a link to the survey
- `survey.html` — the student survey form (Part 2)
- `images/` — photos and logos used on the pages

Styling uses W3.CSS and Font Awesome from a CDN, so the pages need internet access to render. Everything is named lowercase so it behaves the same on Linux (EC2) as it does locally.

## S3 hosting — setup steps
1. Create a bucket (`s3-lizon-bucket-1`, region `us-east-1`).
2. Turn off "Block all public access".
3. Properties → enable Static website hosting, set index document to `index.html`.
4. Add a public-read bucket policy (`s3:GetObject` on `arn:aws:s3:::s3-lizon-bucket-1/*`).
5. Upload `index.html`, `survey.html`, and `images/`.
6. The site URL is the bucket website endpoint under Static website hosting.

## EC2 hosting — setup steps
1. Launch an Amazon Linux 2023 t2.micro instance, key pair `pem-for-assignment-1.pem`, auto-assign public IP enabled.
2. Security group: SSH (22) from my IP, HTTP (80) from anywhere.
3. SSH in from the local terminal:
   ```
   chmod 400 pem-for-assignment-1.pem
   ssh -i pem-for-assignment-1.pem ec2-user@<EC2_PUBLIC_IP>
   ```
4. Install and start Apache:
   ```
   sudo dnf install -y httpd
   sudo systemctl enable --now httpd
   ```
5. Copy the files up (staged in /tmp since /var/www/html is root-owned):
   ```
   scp -i pem-for-assignment-1.pem -r index.html survey.html images ec2-user@<EC2_PUBLIC_IP>:/tmp/
   sudo cp -r /tmp/index.html /tmp/survey.html /tmp/images /var/www/html/
   ```
6. Browse to `http://ec2-54-82-18-73.compute-1.amazonaws.com/index.html` to confirm.

The instance is left running so the public IP stays valid for grading.
