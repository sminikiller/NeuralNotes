FROM node:22-alpine
WORKDIR /app
COPY package.json server.mjs streaming.mjs auth.mjs deepseek.mjs platform.mjs plans.mjs start.mjs ./
USER node
ENV NN_BIND=0.0.0.0
EXPOSE 8787
CMD ["node", "start.mjs"]
