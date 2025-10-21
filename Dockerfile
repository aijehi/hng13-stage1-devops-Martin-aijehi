# =========================================================
# Dockerfile for Aston's Flask App
# =========================================================

# Use an official lightweight Python image
FROM python:3.11-slim

# Set working directory
WORKDIR /app

# Copy dependency list and install requirements
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Expose the app port (this will match your script’s APP_PORT)
EXPOSE 8080

# Command to start the app
CMD ["python", "app.py"]

