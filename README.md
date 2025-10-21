# hng13-stage1-devops-Martin-aijehi
Automated Dockerized App Deployment (deploy.sh)

This project automates the end-to-end deployment of a Dockerized application to a remote Linux server using a single Bash script — deploy.sh.

The script performs:

🔧 Remote server setup (installs Docker, Docker Compose, and Nginx)

🐳 Container build and deployment directly from a Git repository

🌐 Nginx reverse proxy configuration for HTTP access

🧠 Smart validation, logging, and error handling at every step

It’s designed to be idempotent, meaning you can safely re-run it without breaking existing deployments — perfect for repeatable, production-grade setups.
