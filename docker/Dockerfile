FROM quay.io/amery/docker-apptly-builder:latest

# Playwright/Chromium dependencies for headless browser testing
# and MCP screenshot support (@playwright/mcp).
# These are runtime libraries only — no -dev packages needed.
# Generated via: pnpm dlx playwright install-deps --dry-run chromium
#
RUN apt-get update \
	&& apt-get dist-upgrade -y \
	&& apt-get install -y --no-install-recommends \
	libasound2t64 \
	libatk-bridge2.0-0t64 \
	libatk1.0-0t64 \
	libatspi2.0-0t64 \
	libcairo2 \
	libcups2t64 \
	libdbus-1-3 \
	libdrm2 \
	libgbm1 \
	libnspr4 \
	libnss3 \
	libpango-1.0-0 \
	libx11-6 \
	libxcb1 \
	libxcomposite1 \
	libxdamage1 \
	libxext6 \
	libxfixes3 \
	libxkbcommon0 \
	libxrandr2 \
	xvfb \
	fonts-noto-color-emoji \
	fonts-unifont \
	libfontconfig1 \
	libfreetype6 \
	xfonts-cyrillic \
	xfonts-scalable \
	fonts-liberation \
	fonts-ipafont-gothic \
	fonts-wqy-zenhei \
	fonts-tlwg-loma-otf \
	fonts-freefont-ttf \
	&& apt-get clean

# Install Chromium globally for Playwright/MCP use.
ENV PLAYWRIGHT_BROWSERS_PATH=/usr/lib/playwright
RUN npx playwright install chromium
