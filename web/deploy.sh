#!/bin/sh
# Copies only what the site needs into build/site and deploys it. Uses the Cloudflare token in relay/.env.
set -e
cd "$(dirname "$0")"
rm -rf ../build/site && mkdir -p ../build/site
cp -R index.html faq.html privacy.html style.css main.js mark.svg mark-light.svg fonts img shots ../build/site/
set -a; . ../relay/.env; set +a
npx --prefix ../relay wrangler deploy
