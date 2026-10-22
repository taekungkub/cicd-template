# mock backend: Node stdlib ไม่มี dependency → ไม่ต้อง npm ci
FROM node:20-alpine
WORKDIR /app
COPY package.json server.js ./
USER node
EXPOSE 3000
CMD ["node", "server.js"]
