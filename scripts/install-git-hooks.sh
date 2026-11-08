#!/bin/sh
# Point this clone's commit and push hooks at the personal-details check.
set -eu
root=$(git rev-parse --show-toplevel)
hooks=$root/.git/hooks
mkdir -p "$hooks"
cat > "$hooks/pre-commit" << 'EOF'
#!/bin/sh
root=$(git rev-parse --show-toplevel)
exec "$root/scripts/check-no-personal-details.sh"
EOF
cat > "$hooks/pre-push" << 'EOF'
#!/bin/sh
root=$(git rev-parse --show-toplevel)
exec "$root/scripts/check-no-personal-details.sh" --all
EOF
chmod +x "$hooks/pre-commit" "$hooks/pre-push" "$root/scripts/check-no-personal-details.sh"
printf 'Installed pre-commit and pre-push checks in this clone.\n'
