FROM node:20-slim

# Install LMDB runtime dependency
RUN apt-get update && apt-get install -y \
    liblmdb0 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy package files
COPY package.json ./
COPY index.js ./

# Install elkyn-store
RUN npm install

# Run the test
CMD ["npm", "start"]