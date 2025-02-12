FROM nginx:stable-alpine

EXPOSE 80
EXPOSE 443
CMD ["nginx", "-g", "daemon off;"]
