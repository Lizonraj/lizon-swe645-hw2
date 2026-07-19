# Dockerfile — packages the student application into a container. Written by Lizon Raj for SWE 645. Assignment 2.
  
FROM nginx:1.27-alpine
  
COPY site/ /usr/share/nginx/html/
  
EXPOSE 80