# Liten, säker basbild — Alpine är ~50MB istället för ~300MB
FROM node:20-alpine

WORKDIR /app

# Kopiera package-filer och installera beroenden först
# (separata steg = bättre Docker-cachning vid kodändringar)
COPY package*.json ./
RUN npm ci --omit=dev

# Kopiera resten av koden
COPY . .

# Dokumentera vilken port containern lyssnar på
EXPOSE 3000

# Kör inte som root i produktion
USER node

CMD ["npm", "start"]