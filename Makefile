# ft_transcendence - Main Makefile
# School 42 project - Docker management
SHELL := /bin/bash

.DEFAULT_GOAL := vault

# -----------------------------------------------------------------------------
# Environment & IP detection
# -----------------------------------------------------------------------------

# Load environment variables from .env file (only what we REALLY want from there)
ifeq ($(shell test -f .env && echo true),true)
  FRONTEND_PORT := $(shell grep -E '^FRONTEND_PORT=' .env 2>/dev/null | cut -d '=' -f2 | tr -d ' ')
endif

# Set defaults if not found in .env
FRONTEND_PORT ?= 3000

# Auto-detect LAN_IP based on OS and network interface
UNAME_S := $(shell uname -s)

ifeq ($(UNAME_S),Darwin)  # macOS
    DETECTED_LAN_IP := $(shell ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo "127.0.0.1")
else ifeq ($(UNAME_S),Linux)
    DETECTED_LAN_IP := $(shell hostname -I | awk '{print $$1}' 2>/dev/null || echo "127.0.0.1")
else
    # Windows PowerShell (Git Bash fallback)
    DETECTED_LAN_IP := $(shell powershell.exe -Command "(Get-NetIPAddress -AddressFamily IPv4).IPAddress" | head -1 2>/dev/null || echo "127.0.0.1")
endif

# Final LAN_IP value used everywhere
LAN_IP ?= $(DETECTED_LAN_IP)

update-env-ip:
	@echo "🔄 Detecting operating system..."
	@unameOut="$(UNAME_S)"; \
	echo "🖥️ OS Detected: $$unameOut"; \
	echo "🔄 Updating LAN_IP in .env..."; \
	if [ -f .env ]; then \
		if echo "$$unameOut" | grep -i "darwin" >/dev/null; then \
			sed -i '' "s/^LAN_IP=.*/LAN_IP=$(LAN_IP)/" .env || true; \
		elif echo "$$unameOut" | grep -i "linux" >/dev/null; then \
			sed -i "s/^LAN_IP=.*/LAN_IP=$(LAN_IP)/" .env || true; \
		else \
			powershell.exe -Command \
				"(Get-Content .env) -replace 'LAN_IP=.*', 'LAN_IP=$(LAN_IP)' | Set-Content .env" || true; \
		fi; \
	else \
		echo "LAN_IP=$(LAN_IP)" > .env; \
	fi; \
	echo "🌐 LAN_IP set to: $(LAN_IP)"

# -----------------------------------------------------------------------------
# Top-level commands
# -----------------------------------------------------------------------------

# Complete automated development workflow (clean → docker → auto-unseal)
vault: clean update-env-ip
	@echo ""
	@echo "🔐 UNsealing Vault..."
	@echo ""
	@if [ -f .vault-keys ]; then \
		echo "✅ .vault-keys found – treating this as an already configured machine."; \
		$(MAKE) vault-init-existing; \
	else \
		echo "ℹ️  .vault-keys not found – running first-time Vault setup."; \
		$(MAKE) vault-init-first-time; \
	fi
	@echo ""
	@echo "🚀 Starting all services now that Vault is unsealed..."
	@if [ -f .vault-keys ]; then \
		. ./.vault-keys; \
		export VAULT_TOKEN; \
		docker compose up -d; \
	else \
		docker compose up -d; \
	fi
	@sleep 3
	@echo ""
	@echo "✅ Development environment ready!"
	@echo ""
	@echo "📋 Services available at:"
	@echo "  Frontend:     https://$(LAN_IP)"
	@echo "  Gateway:      https://$(LAN_IP)/api/"
	@echo "  WebSocket:    wss://$(LAN_IP)/ws/"
	@echo "  Kibana:       https://$(LAN_IP)/kibana/"
	@echo ""
	@echo "📚 API Documentation (Swagger):"
	@echo "  Gateway:      https://$(LAN_IP)/api/docs"
	@echo "  Auth Service: https://$(LAN_IP)/auth-docs/"
	@echo "  User Service: https://$(LAN_IP)/user-docs/"
	@echo "  WS Service:   https://$(LAN_IP)/ws-docs/"
	@echo ""
	@echo "🔍 Logging & Monitoring:"
	@echo "  Elasticsearch: https://$(LAN_IP)/elasticsearch/"
	@echo "  Kibana:        https://$(LAN_IP)/kibana/"
	@echo ""
	@echo "🔧 Internal Services:"
	@echo "  Vault:        http://vault-service:8200"
	@echo ""
	@echo "💡 Tip: Run 'make logs' to follow logs"

# Save Vault keys for automated workflow (one-time setup)
save-vault-keys:
	@echo "🔐 Saving Vault keys for automated workflow..."
	@echo ""
	@echo "⚠️  This file will store your VAULT_TOKEN and unseal keys"
	@echo "⚠️  It's added to .gitignore for security"
	@echo ""
	@read -p "Enter your VAULT_TOKEN: " token; \
	echo "VAULT_TOKEN=$$token" > .vault-keys
	@echo ""
	@echo "📝 Now enter 3 unseal keys (you only need 3 of the 5):"
	@read -p "Enter Unseal Key 1: " key1; \
	echo "UNSEAL_KEY_1=$$key1" >> .vault-keys
	@read -p "Enter Unseal Key 2: " key2; \
	echo "UNSEAL_KEY_2=$$key2" >> .vault-keys
	@read -p "Enter Unseal Key 3: " key3; \
	echo "UNSEAL_KEY_3=$$key3" >> .vault-keys
	@chmod 600 .vault-keys
	@echo ""
	@echo "✅ Vault keys saved to .vault-keys (secure permissions set)"
	@echo "🎯 You can now use 'make' or 'make start' for automated workflow!"

# Automatically unseal Vault using saved keys
auto-unseal:
	@if [ ! -f .vault-keys ]; then \
		echo "❌ .vault-keys file not found!"; \
		echo "📝 Run 'make save-vault-keys' first to save your keys"; \
		exit 1; \
	fi
	@echo "🔐 Auto-unsealing Vault..."
	@if ! docker ps | grep -q vault_service; then \
		echo "❌ Vault container is not running. Starting it now..."; \
		docker compose up -d vault-service; \
		sleep 5; \
	fi
	@. ./.vault-keys; \
	echo "🔓 Unsealing with key 1..."; \
	docker exec vault_service vault operator unseal $$UNSEAL_KEY_1 > /dev/null; \
	echo "🔓 Unsealing with key 2..."; \
	docker exec vault_service vault operator unseal $$UNSEAL_KEY_2 > /dev/null; \
	echo "🔓 Unsealing with key 3..."; \
	docker exec vault_service vault operator unseal $$UNSEAL_KEY_3 > /dev/null
	@echo "✅ Vault unsealed successfully!"

# Quick start without cleaning (docker → auto-unseal)
start:
	@echo ""
	@echo "🎯 Quick starting all services..."
	@echo ""
	@$(MAKE) docker-no-logs
	@echo ""
	@if [ -f .vault-keys ]; then \
		echo "🔐 Auto-unsealing Vault..."; \
		$(MAKE) auto-unseal; \
	else \
		echo "⚠️  .vault-keys not found. Run 'make save-vault-keys' first for automation"; \
		echo "📝 Or unseal manually now..."; \
		echo ""; \
		$(MAKE) unseal; \
	fi
	@echo ""
	@echo "🚀 Starting all services now that Vault is unsealed..."
	@if [ -f .vault-keys ]; then \
		. ./.vault-keys; \
		export VAULT_TOKEN; \
		docker compose up -d; \
	else \
		docker compose up -d; \
	fi
	@sleep 3
	@echo ""
	@echo "✅ All services ready!"
	@echo ""
	@echo "📋 Services available at:"
	@echo "  Frontend:     https://$(LAN_IP)"
	@echo "  Gateway:      https://$(LAN_IP)/api/"
	@echo "  WebSocket:    wss://$(LAN_IP)/ws/"
	@echo "  Kibana:       https://$(LAN_IP)/kibana/"
	@echo ""
	@echo "📚 API Documentation (Swagger):"
	@echo "  Gateway:      https://$(LAN_IP)/api/docs"
	@echo "  Auth Service: https://$(LAN_IP)/auth-docs/"
	@echo "  User Service: https://$(LAN_IP)/user-docs/"
	@echo "  WS Service:   https://$(LAN_IP)/ws-docs/"
	@echo ""
	@echo "🔍 Logging & Monitoring:"
	@echo "  Elasticsearch: https://$(LAN_IP)/elasticsearch/"
	@echo "  Kibana:        https://$(LAN_IP)/kibana/"
	@echo ""
	@echo "🔧 Internal Services:"
	@echo "  Vault:        http://vault-service:8200"
	@echo ""
	@echo "💡 Tip: Run 'make logs' to follow logs"

# Unseal Vault
unseal: up-vault
	@echo "🔐 Unsealing Vault..."
	@echo "⏳ Waiting for Vault to be ready..."
	@sleep 3
	@if ! docker ps | grep -q vault_service; then \
		echo "❌ Vault container is not running. Starting it now..."; \
		docker compose up -d vault-service; \
		sleep 5; \
	fi
	@read -s -p "Enter Unseal Key 1: " key1; echo; \
	docker exec -it vault_service vault operator unseal $$key1; \
	read -s -p "Enter Unseal Key 2: " key2; echo; \
	docker exec -it vault_service vault operator unseal $$key2; \
	read -s -p "Enter Unseal Key 3: " key3; echo; \
	docker exec -it vault_service vault operator unseal $$key3
	@echo "✅ Vault should be unlocked"

up-vault:
	@echo "🚀 Starting vault-service..."
	docker compose up -d vault-service

# Automated Vault first-time setup (all steps from README lines 38-116)
vault-init-first-time:
	@echo "🔐 Automated Vault First-Time Setup"
	@echo "===================================="
	@echo ""
	@echo "Step 1: Building and starting Vault..."
	@$(MAKE) build
	@$(MAKE) up-vault
	@echo "⏳ Waiting for Vault to be ready..."
	@sleep 5
	@echo ""
	@echo "Step 2: Initializing Vault (getting tokens and keys)..."
	@echo "⚠️  This will generate Initial Root Token and 5 Unseal Keys"
	@echo "⚠️  SAVE THESE SECURELY - they are unique to this machine!"
	@echo ""
	@docker exec -it vault_service vault operator init || \
		(echo "❌ Vault initialization failed. Check if container is running." && exit 1)
	@echo ""
	@echo "✅ Vault initialized!"
	@echo "📝 IMPORTANT: Save the Initial Root Token and 5 Unseal Keys securely"
	@echo ""
	@echo "Step 2b: Save your Initial Root Token and 3 Unseal Keys for automation"
	@$(MAKE) save-vault-keys
	@echo ""
	@echo "Step 3: Setting up VAULT environment variables..."
	@echo "⚠️  Please enter your Initial Root Token from Step 2:"
	@read -p "VAULT_TOKEN: " token && \
	export VAULT_TOKEN="$$token" && \
	export VAULT_ADDR='127.0.0.1:8200' && \
	echo "✅ VAULT_TOKEN and VAULT_ADDR exported for this session"
	@echo ""
	@echo "Step 4: Unsealing Vault..."
	@echo "⚠️  You will need 3 of the 5 Unseal Keys from Step 2"
	@read -s -p "Enter Unseal Key 1: " key1 && echo && \
	docker exec vault_service vault operator unseal $$key1 || exit 1
	@read -s -p "Enter Unseal Key 2: " key2 && echo && \
	docker exec vault_service vault operator unseal $$key2 || exit 1
	@read -s -p "Enter Unseal Key 3: " key3 && echo && \
	docker exec vault_service vault operator unseal $$key3 || exit 1
	@echo "✅ Vault unsealed!"
	@echo ""
	@echo "Step 5: Logging into Vault..."
	@echo "⚠️  Please re-enter your VAULT_TOKEN for login:"
	@read -p "VAULT_TOKEN: " token && \
	docker exec -e VAULT_TOKEN="$$token" vault_service vault login -method=token token="$$token" > /dev/null 2>&1 || \
		(echo "⚠️  Login step skipped (may already be logged in)" && true)
	@echo "✅ Logged into Vault!"
	@echo ""
	@echo "Step 6: Loading secrets..."
	@echo "⚠️  Please enter your VAULT_TOKEN again for secret operations:"
	@read -p "VAULT_TOKEN: " token && \
	echo "📦 Enabling KV v2 secrets engine..." && \
	docker exec -e VAULT_TOKEN="$$token" vault_service vault secrets enable -path=secret kv-v2 2>/dev/null || \
		echo "⚠️  KV engine already enabled (this is OK)" && \
	echo "🔑 Adding JWT secret..." && \
	docker exec -e VAULT_TOKEN="$$token" vault_service vault kv put secret/jwt JWT_SECRET='secretjwt' || \
		(echo "❌ Failed to add JWT secret. Ensure Vault is unsealed and logged in." && exit 1) && \
	echo "🔒 Creating SSL certificates..." && \
	mkdir -p certs && \
	openssl req -x509 -nodes -days 365 \
		-newkey rsa:2048 \
		-keyout certs/server.key \
		-out certs/server.crt \
		-subj "/CN=localhost" 2>/dev/null || \
		(echo "⚠️  SSL certs may already exist (this is OK)" && true) && \
	echo "🔒 Adding SSL certificates to Vault..." && \
	docker exec -e VAULT_TOKEN="$$token" vault_service vault kv put secret/ssl \
		CRT="$$(cat certs/server.crt)" KEY="$$(cat certs/server.key)" && \
		rm -rf certs || \
		(echo "❌ Failed to add SSL secrets. Ensure Vault is unsealed and logged in." && exit 1)
	@echo "✅ Secrets loaded!"
	@echo ""
	@echo "Step 7: Starting all containers..."
	@$(MAKE) up
	@echo ""
	@echo "✅ Vault first-time setup complete!"
	@echo "📝 Next steps - Run these commands in your shell:"
	@echo "   export VAULT_TOKEN='your_initial_root_token'"
	@echo "   export VAULT_ADDR='127.0.0.1:8200'"

# Automated Vault setup for already configured machines (README lines 119-150)
vault-init-existing:
	@echo "🔐 Automated Vault Setup (Already Configured)"
	@echo "============================================="
	@echo ""
	@echo "Step 1: Building and starting Vault..."
	@$(MAKE) build
	@$(MAKE) up-vault
	@echo "⏳ Waiting for Vault to be ready..."
	@sleep 5
	@echo ""
	@echo "Step 2: Setting up VAULT environment variables..."
	@if [ -z "$$VAULT_TOKEN" ]; then \
		echo "⚠️  VAULT_TOKEN not found in environment."; \
		echo "⚠️  Please enter your Initial Root Token:"; \
		read -p "VAULT_TOKEN: " token && \
		export VAULT_TOKEN="$$token" && \
		export VAULT_ADDR='127.0.0.1:8200' && \
		echo "✅ VAULT_TOKEN and VAULT_ADDR exported for this session"; \
	else \
		export VAULT_ADDR='127.0.0.1:8200' && \
		echo "✅ Using existing VAULT_TOKEN from environment" && \
		echo "✅ VAULT_ADDR set to 127.0.0.1:8200"; \
	fi
	@echo ""
	@echo "Step 3: Unsealing Vault..."
	@echo "⚠️  You will need 3 of your 5 Unseal Keys"
	@read -s -p "Enter Unseal Key 1: " key1 && echo && \
	docker exec vault_service vault operator unseal $$key1 || exit 1
	@read -s -p "Enter Unseal Key 2: " key2 && echo && \
	docker exec vault_service vault operator unseal $$key2 || exit 1
	@read -s -p "Enter Unseal Key 3: " key3 && echo && \
	docker exec vault_service vault operator unseal $$key3 || exit 1
	@echo "✅ Vault unsealed!"
	@echo ""
	@echo "Step 4: Starting all containers..."
	@$(MAKE) up
	@echo ""
	@echo "✅ Vault setup complete for existing configuration!"
	@echo "📝 Next steps - Run these commands in your shell:"
	@echo "   export VAULT_TOKEN='your_initial_root_token'"
	@echo "   export VAULT_ADDR='127.0.0.1:8200'"

clean:
	@echo "🧹 Cleaning up ALL Docker resources and local data..."
	docker compose down -v --rmi all 2>/dev/null || true
	@echo "🧹 Pruning Docker system..."
	docker system prune -a -f --volumes
	docker builder prune -a -f
	@echo "🗑️  Removing local DB files..."
	@rm -f backend/user-service/data/*.db backend/user-service/data/*.db-journal || true
	@rm -f backend/auth-service/data/*.db backend/auth-service/data/*.db-journal || true
	@rm -f backend/ws-service/data/*.db backend/ws-service/data/*.db-journal || true
	@rm -f *.db *.db-journal || true
	@echo "🗑️  Removing Prisma leftovers..."
	@rm -rf backend/auth-service/prisma backend/user-service/prisma backend/prisma prisma generated/prisma || true
	@find backend -type d -name "prisma" -exec rm -rf {} + 2>/dev/null || true
	@find backend -type f -path "*/prisma/*.db" -delete 2>/dev/null || true
	@find backend -type f -path "*/prisma/*.db-journal" -delete 2>/dev/null || true
	@echo "🧹 Removing frontend build artifacts..."
	@rm -rf frontend/dist frontend/node_modules/.vite frontend/.vite frontend/.cache || true
	@echo "🧹 Removing backend build artifacts..."
	@find backend -type d -name "dist" -exec rm -rf {} + 2>/dev/null || true
	@find backend -type f -name "*.tsbuildinfo" -delete 2>/dev/null || true
	@find backend -type d -name ".cache" -exec rm -rf {} + 2>/dev/null || true
	@find backend -type d -path "*/node_modules/.cache" -exec rm -rf {} + 2>/dev/null || true
	@echo "🧹 Removing logs..."
	@find backend -type f -name "*.log" -delete 2>/dev/null || true
	@rm -f *.log
	@rm -rf logs
	@echo "🧹 Removing WAF certificates..."
	@rm -rf waf/certs
	@echo "🧹 Removing Vault dependencies..."
	@chmod +x start-dev.sh
	@./start-dev.sh
	@echo "✅ Full cleanup complete!"

help:
	@echo "🚀 ft_transcendence - Docker Management"
	@echo
	@echo "🎯 Main commands:"
	@echo "  make restart-logs      - Stop, build, start all services and follow logs (no Vault)"
	@echo "  make build             - Build all Docker images"
	@echo "  make up                - Start all services"
	@echo "  make down              - Stop all services"
	@echo "  make logs              - Follow logs from all services"
	@echo "  make restart           - Restart all services (including Vault)"
	@echo "  make restart-services  - Restart services only (preserve Vault state)"
	@echo "  make clean             - Clean all Docker resources and local DBs"
	@echo "  make status            - Show service status"
	@echo
	@echo "Rebuild:"
	@echo "  make clear-cache       - Clear frontend build cache"
	@echo "  make rebuild-frontend  - Rebuild frontend only (no cache)"
	@echo "  make rebuild-all       - Rebuild ALL services (no cache)"
	@echo
	@echo "ELK:"
	@echo "  make up-elk            - Start ELK stack (ES + Logstash + Kibana + Filebeat)"

# -----------------------------------------------------------------------------
# Basic checks
# -----------------------------------------------------------------------------

logs:
	@echo "📋 Following logs from all services (Ctrl+C to stop)..."
	docker compose logs -f

status:
	@echo "📊 Service Status:"
	@docker compose ps

# -----------------------------------------------------------------------------
# ELK & rebuild helpers
# -----------------------------------------------------------------------------

up-elk:
	@echo "🚀 Starting ELK Stack..."
	docker compose up -d elasticsearch logstash kibana filebeat kibana-setup
	@echo "✅ ELK Stack started!"
	@echo "📊 Kibana: https://$(LAN_IP)/kibana/ (elastic / changeme)"

clear-cache:
	@echo "🧹 Clearing frontend build cache..."
	@rm -rf frontend/dist frontend/node_modules/.vite frontend/.vite frontend/.cache
	@echo "✅ Cache cleared!"

rebuild-frontend: update-env-ip clear-cache
	@echo "🔨 Force rebuilding frontend (no cache)..."
	@docker compose stop frontend user-service auth-service gateway-service ws-service waf 2>/dev/null || true
	@docker compose rm -f frontend user-service auth-service gateway-service ws-service waf 2>/dev/null || true
	@if [ -f .env ]; then \
		set -a; . .env; set +a; \
	fi; \
	docker compose build --no-cache frontend
	@docker compose up -d
	@echo "✅ Frontend rebuilt!"
	@echo "⚠️  Clear your browser cache or hard refresh."

.PHONY: \
  vault \
  vault-init-first-time \
  vault-init-existing \
  start \
  save-vault-keys \
  auto-unseal \
  unseal \
  clean \
  help \
  logs \
  status \
  update-env-ip \
  up-elk \
  clear-cache \
  rebuild-frontend