#!/bin/bash

echo "🚀 Starting All Discourse Development Services"
echo ""

# Check if Discourse container is running
if ! docker ps | grep -q discourse_dev; then
    echo "❌ Discourse container is not running!"
    echo "   Start it first: cd ~/discourse && ./bin/docker/boot_dev"
    exit 1
fi

# Check if unicorn is already running
if docker exec discourse_dev bash -c "ps aux | grep -q 'unicorn master' | grep -v grep" 2>/dev/null; then
    echo "⚠️  Unicorn is already running"
    echo "   Stop it first (Ctrl+C in the terminal where it's running)"
    echo "   Or run: docker exec discourse_dev pkill -f 'unicorn master'"
    exit 1
fi

echo "📋 You need to run these commands in 3 separate terminals:"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "TERMINAL 1 - Unicorn (Discourse Backend):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "cd ~/discourse"
echo "docker exec -e UNICORN_PORT=3000 -u discourse:discourse -w /src discourse_dev bundle exec bin/unicorn"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "TERMINAL 2 - Ember CLI (Frontend):"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "cd ~/discourse"
echo "./bin/docker/ember-cli"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "TERMINAL 3 - Theme Watcher:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "cd /home/bnb/Desktop/discourse_theme/compound-governance-widget"
echo "discourse_theme watch ."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📝 Start them in order: Terminal 1 → Terminal 2 → Terminal 3"
echo ""
echo "🌐 Access Discourse at: http://localhost:4200"
echo ""





