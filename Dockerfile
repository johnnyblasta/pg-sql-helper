# Liten, säker basbild — Alpine är ~50MB istället för ~300MB
# Minst 24.22.1 krävs: åtgärdar CVE-2026-111497 (Brotli RCE, "node2shell").
# Node 20 är end-of-life och får ingen fix.
FROM node:24.22.1-alpine

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